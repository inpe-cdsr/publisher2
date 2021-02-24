from copy import deepcopy
from datetime import datetime, timedelta
from glob import glob
from json import dumps
from os import walk
from os.path import join as os_path_join, sep as os_path_sep
from re import search

from werkzeug.exceptions import InternalServerError
from xmltodict import parse as xmltodict_parse

from publisher.common import fill_string_with_left_zeros, print_line
from publisher.environment import PR_LOGGING_LEVEL
from publisher.logger import create_logger
from publisher.model import PostgreSQLCatalogTestConnection, PostgreSQLPublisherConnection


# create logger object
logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


def convert_xml_to_dict(xml_path):
    '''Read an XML file, convert it to a dictionary and return it.'''

    with open(xml_path, 'r') as data:
        return xmltodict_parse(data.read())


##################################################
# Item
##################################################

def get_collection_from_xml_as_dict(xml_as_dict, radio_processing):
    '''Get collection information from XML file as dictionary.'''

    collection = {
        'satellite': xml_as_dict['satellite']['name'] + xml_as_dict['satellite']['number'],
        'sensor': xml_as_dict['satellite']['instrument']['#text'],
        # geometric processing: L2, L4, etc.
        'geo_processing': xml_as_dict['image']['level'],
        # radiometric processing: DN or SR
        'radio_processing': radio_processing,
    }

    # create collection name based on its properties (e.g. `CBERS4A_MUX_L2_DN`)
    collection['name'] = (
        f"{collection['satellite']}_{collection['sensor']}_"
        f"L{collection['geo_processing']}_{collection['radio_processing']}"
    )

    # create collection description based on its properties (e.g. `CBERS4A MUX Level2 DN dataset`)
    collection['description'] = (
        f"{collection['satellite']} {collection['sensor']} "
        f"Level {collection['geo_processing']} {collection['radio_processing']} "
        'dataset'
    )

    return collection


def get_properties_from_xml_as_dict(xml_as_dict, collection):
    '''Get properties information from XML file as dictionary.'''

    # get the item's properties
    properties = {
        # get just the date and time of the string
        'datetime': xml_as_dict['viewing']['center'][0:19],
        # fill path and row with left zeros in order to create the item name
        'path': fill_string_with_left_zeros(xml_as_dict['image']['path']),
        'row': fill_string_with_left_zeros(xml_as_dict['image']['row']),
        # CQ fills it
        # 'cloud_cover': '',
        'satellite': collection['satellite'],
        'sensor': collection['sensor'],
        # 'deleted': item['deleted']
    }

    # create item name based on its properties (e.g. `CBERS4A_MUX_070122_20200813`)
    properties['name'] = (
        f"{collection['satellite']}_{collection['sensor']}_"
        f"{properties['path']}{properties['row']}_"
        f"{properties['datetime'].split('T')[0].replace('-', '')}_"
        f"L{collection['geo_processing']}_{collection['radio_processing']}"
    )

    # convert path and row to integer
    properties['path'] = int(properties['path'])
    properties['row'] = int(properties['row'])

    # if there is sync loss in the XML file, then I get it and add it in properties
    if 'syncLoss' in xml_as_dict['image']:
        sync_loss_bands = xml_as_dict['image']['syncLoss']['band']
        # get the max value from the sync losses
        properties['sync_loss'] = max([
            float(sync_loss_band['#text']) for sync_loss_band in sync_loss_bands
        ])

    # if there is sun position in the XML file, then I get it and add it in properties
    if 'sunPosition' in xml_as_dict['image']:
        properties['sun_position'] = dict(xml_as_dict['image']['sunPosition'])
        # rename key from 'sunAzimuth' to 'sun_azimuth'
        properties['sun_position']['sun_azimuth'] = properties['sun_position'].pop('sunAzimuth')
        # convert values to float
        for key in properties['sun_position']:
            properties['sun_position'][key] = float(properties['sun_position'][key])

    return properties


def get_bbox_from_xml_as_dict(xml_as_dict):
    '''Get bounding box information from XML file as dictionary.'''

    # Label: UL - upper left; UR - upper right; LR - bottom right; LL - bottom left

    # create bbox object
    # specification: https://tools.ietf.org/html/rfc7946#section-5
    # `all axes of the most southwesterly point followed by all axes of the more northeasterly point`
    return [
        xml_as_dict['image']['imageData']['LL']['longitude'], # bottom left longitude
        xml_as_dict['image']['imageData']['LL']['latitude'], # bottom left latitude
        xml_as_dict['image']['imageData']['UR']['longitude'], # upper right longitude
        xml_as_dict['image']['imageData']['UR']['latitude'], # upper right latitude
    ]


def get_geometry_from_xml_as_dict(xml_as_dict, epsg=4326):
    '''Get geometry information (i.e. footprint) from an XML file as dictionary.'''

    # Label: UL - upper left; UR - upper right; LR - bottom right; LL - bottom left

    # create geometry object
    # specification: https://tools.ietf.org/html/rfc7946#section-3.1.6
    return {
        'type': 'Polygon',
        'coordinates': [[
            [xml_as_dict['image']['imageData']['UL']['longitude'], xml_as_dict['image']['imageData']['UL']['latitude']],
            [xml_as_dict['image']['imageData']['UR']['longitude'], xml_as_dict['image']['imageData']['UR']['latitude']],
            [xml_as_dict['image']['imageData']['LR']['longitude'], xml_as_dict['image']['imageData']['LR']['latitude']],
            [xml_as_dict['image']['imageData']['LL']['longitude'], xml_as_dict['image']['imageData']['LL']['latitude']],
            [xml_as_dict['image']['imageData']['UL']['longitude'], xml_as_dict['image']['imageData']['UL']['latitude']]
        ]],
        'crs': {'type': 'name','properties': {'name': f'EPSG:{epsg}'}}
    }


def create_items_from_xml_as_dict(xml_as_dict, assets):
    '''
    Return a list of items based on an XML file as dictionary and the
    radiometric processing information the user chose.
    '''

    if 'leftCamera' in xml_as_dict:
        xml_as_dict = xml_as_dict['leftCamera']

    # if user chose `DN` and `SR` radiometric processings, then create both items
    if 'DN' in assets and 'SR' in assets:
        # create DN item
        dn_item = {}
        dn_item['collection'] = get_collection_from_xml_as_dict(xml_as_dict, 'DN')
        dn_item['properties'] = get_properties_from_xml_as_dict(xml_as_dict, dn_item['collection'])
        dn_item['bbox'] = get_bbox_from_xml_as_dict(xml_as_dict)
        dn_item['geometry'] = get_geometry_from_xml_as_dict(xml_as_dict)
        dn_item['assets'] = assets['DN']

        # create SR item from DN item, because they have almost the same information
        # the only different information they have is the radiometric processing
        sr_item = deepcopy(dn_item)
        sr_item['collection']['radio_processing'] = 'SR'
        sr_item['collection']['name'] = sr_item['collection']['name'].replace('DN', 'SR')
        sr_item['collection']['description'] = sr_item['collection']['description'].replace('DN', 'SR')
        sr_item['properties']['name'] = sr_item['properties']['name'].replace('DN', 'SR')
        sr_item['assets'] = assets['SR']

        # return both `DN` and `SR` items
        return [dn_item, sr_item]

    # if user chose just `DN` radiometric processing, create a collection with it
    if 'DN' in assets:
        item = {
            'collection': get_collection_from_xml_as_dict(xml_as_dict, 'DN'),
            'assets': assets['DN']
        }

    # if user chose just `SR` radiometric processing, create a collection with it
    elif 'SR' in assets:
        item = {
            'collection': get_collection_from_xml_as_dict(xml_as_dict, 'SR'),
            'assets': assets['SR']
        }

    # extract other information to the item
    item['properties'] = get_properties_from_xml_as_dict(xml_as_dict, item['collection'])
    item['bbox'] = get_bbox_from_xml_as_dict(xml_as_dict)
    item['geometry'] = get_geometry_from_xml_as_dict(xml_as_dict)

    # return either `DN` or `SR` item
    return [item]


def create_item_and_get_insert_clauses(dir_path, dn_xml_file_path, assets, df_collections):
    print_line()

    items_insert = []
    errors_insert = []

    logger.info(f'dn_xml_file_path: {dn_xml_file_path}')
    logger.info(f'assets: {assets}')

    # convert DN XML file in a dictionary
    xml_as_dict = convert_xml_to_dict(dn_xml_file_path)

    # if there is NOT `DN` information in the XML file, then the method returns None
    if 'prdf' not in xml_as_dict:
        return None

    xml_as_dict = xml_as_dict['prdf']
    # logger.info(f'xml_as_dict: {xml_as_dict}')

    # list of items (e.g. [dn_item, sr_item])
    items = create_items_from_xml_as_dict(xml_as_dict, assets)
    logger.info(f'items size: {len(items)}\n')

    for item in items:
        print_line()
        logger.info(f'item: {item}\n')
        logger.info(f"item[collection][name]: {item['collection']['name']}")

        # get collection id from dataframe
        collection = df_collections.loc[
            df_collections['name'] == item['collection']['name']
        ].reset_index(drop=True)
        logger.info(f'collection:\n{collection}')

        # if `collection` is an empty dataframe, a collection was not found by its name,
        # then save the warning and ignore it
        if len(collection.index) == 0:
            # check if the collection has not already been added to the errors list
            if not any(e['metadata']['collection'] == item['collection']['name'] \
                    for e in errors_insert):
                errors_insert.append(
                    PostgreSQLPublisherConnection.create_task_error_insert_clause({
                        'message': (
                            f'There is metadata to the `{item["collection"]["name"]}` collection, '
                            'however this collection does not exist in the database.'
                        ),
                        'metadata': {'collection': item['collection']['name']},
                        'type': 'warning'
                    })
                )
            continue

        collection_id = collection.at[0, 'id']
        logger.info(f'collection_id: {collection_id}')

        # create INSERT clause based on item metadata
        insert = PostgreSQLCatalogTestConnection.create_item_insert_clause(
            item, collection_id
        )
        logger.info(f'insert: {insert}')
        items_insert.append(insert)

    return items_insert, errors_insert


##################################################
# Generator
##################################################


def decode_scene_dir(scene_dir):
    '''Decode a scene directory, returning its information.'''

    scene_dir_first, scene_dir_second = scene_dir.split('.')

    if scene_dir_first.startswith('CBERS_4'):
        # examples: CBERS_4_MUX_DRD_2020_07_31.13_07_00_CB11
        # or CBERS_4A_MUX_RAW_2019_12_27.13_53_00_ETC2
        # or CBERS_4A_MUX_RAW_2019_12_28.14_15_00

        satellite, number, sensor, _, *date = scene_dir_first.split('_')
        # create satellite name with its number
        satellite = satellite + number
        date = '-'.join(date)
        time = scene_dir_second.split('_')

        if len(time) == 3:
            # this time has just time, then I join the parts (e.g. '13_53_00')
            time = ':'.join(time)
        elif len(time) == 4:
            # this time has NOT just time, then I join the time parts (e.g. '13_53_00_ETC2')
            time = ':'.join(time[0:3])
        else:
            raise InternalServerError(f'Invalid scene dir: {scene_dir}')

    elif scene_dir_first.startswith('CBERS2B') or scene_dir_first.startswith('LANDSAT'):
        # examples: CBERS2B_CCD_20070925.145654
        # or LANDSAT1_MSS_19750907.130000

        satellite, sensor, date = scene_dir_first.split('_')
        time = scene_dir_second

        if len(date) != 8:
            # example: a time should be something like this: '20070925'
            raise InternalServerError(f'Invalid scene dir: {scene_dir}')

        # I build the date string based on the old one (e.g. from '20070925' to '2007-09-25')
        date = f'{date[0:4]}-{date[4:6]}-{date[6:8]}'

        if len(time) != 6:
            # example: a time should be something like this: '145654'
            raise InternalServerError(f'Invalid scene dir: {scene_dir}')

        # I build the time string based on the old one (e.g. from '145654' to '14:56:54')
        time = f'{time[0:2]}:{time[2:4]}:{time[4:6]}'

    else:
        raise InternalServerError(f'Invalid scene dir: {scene_dir}')

    return satellite, sensor, date, time


def is_there_sr_files_in_the_list_of_files(files):
    # example: CBERS_4_AWFI_20201228_157_135_L4_BAND16_GRID_SURFACE.xml
    sr_template = '^[a-zA-Z0-9_]+BAND\d+_GRID_SURFACE.xml$'

    # get just the SR XML files based on the radiometric processing regex
    sr_xml_files = list(filter(lambda f: search(sr_template, f), files))

    # True if sr_xml_files else False
    return bool(sr_xml_files)


class PublisherWalk:
    '''This class is a Generator that encapsulates `os.walk()` generator to return just valid directories.
    A valid directory is a folder that contains XML files.'''

    def __init__(self, BASE_DIR, query, satellite_metadata):
        self.BASE_DIR = BASE_DIR
        self.query = query
        self.satellite_metadata = satellite_metadata
        self.errors_insert = []

        # create an iterator from generator method
        self.__generator_iterator = self.__generator()

    def __is_dir_path_valid(self, dir_path):
        '''Check if `dir_path` parameter is valid based on `query`.'''

        # get dir path starting at `/TIFF`
        index = dir_path.find('TIFF')
        # `splitted_dir_path` example:
        # ['TIFF', 'CBERS4A', '2020_11', 'CBERS_4A_WFI_RAW_2020_11_10.13_41_00_ETC2', '207_148_0', '2_BC_UTM_WGS84']
        splitted_dir_path = dir_path[index:].split(os_path_sep)

        # a valid dir path must have at least five folders (+1 the base path (i.e. /TIFF))
        if len(splitted_dir_path) != 6:
            return False, None, None

        _, satellite_dir, year_month_dir, scene_dir, path_row_dir, level_dir = splitted_dir_path

        # if the informed satellite is not equal to the dir, then the folder is invalid
        if self.query['satellite'] is not None and self.query['satellite'] != satellite_dir:
            return False, None, None

        _, sensor_dir, date_dir, time_dir = decode_scene_dir(scene_dir)

        # if the informed sensor is not equal to the dir, then the folder is invalid
        if self.query['sensor'] is not None and self.query['sensor'] != sensor_dir:
            return False, None, None

        # if the actual dir is not inside the date range, then the folder is invalid
        if self.query['start_date'] is not None and self.query['end_date'] is not None:
            # convert date from str to datetime
            date = datetime.strptime(date_dir, '%Y-%m-%d')

            # if time dir is between 0h and 5h, then consider it one day ago,
            # because date is reception date and not viewing date
            if time_dir >= '00:00:00' and time_dir <= '05:00:00':
                # subtract one day from the date
                date -= timedelta(days=1)

            if not (date >= self.query['start_date'] and date <= self.query['end_date']):
                return False, None, None

        # if the informed path/row is not inside the dir, then the folder is invalid
        if self.query['path'] is not None or self.query['row'] is not None:
            splitted_path_row = path_row_dir.split('_')

            if len(splitted_path_row) == 3:
                # example: `151_098_0`
                path, row, _ = splitted_path_row
            elif len(splitted_path_row) == 5:
                # example: `151_B_141_5_0`
                path, _, row, _, _ = splitted_path_row
            else:
                raise InternalServerError(f'Invalid path/row dir: {path_row_dir}')

            if self.query['path'] is not None and self.query['path'] != int(path):
                return False, None, None

            if self.query['row'] is not None and self.query['row'] != int(row):
                return False, None, None

        # if the level_dir does not start with the informed geo_processing, then the folder is invalid
        if self.query['geo_processing'] is not None and not level_dir.startswith(str(self.query['geo_processing'])):
            # example: `2_BC_UTM_WGS84`
            return False, None, None

        return True, satellite_dir, sensor_dir

    def __get_dn_xml_file_path(self, files, dir_path):
        # example: CBERS_4_AWFI_20201228_157_135_L4_RIGHT_BAND16.xml
        dn_template = '^[a-zA-Z0-9_]+BAND\d+.xml$'

        # get just the DN XML files based on the radiometric processing regex
        # for both DN or SR files, I extract information from a DN XML file
        dn_xml_files = list(filter(lambda f: search(dn_template, f), files))

        if dn_xml_files:
            # `dn_xml_files[0]` gets the first DN XML file
            # `os_path_join` creates a full path to the XML file
            return os_path_join(dir_path, dn_xml_files[0])

        self.errors_insert.append(
            PostgreSQLPublisherConnection.create_task_error_insert_clause({
                'type': 'warning',
                'message': 'There is NOT a DN XML file in this folder, then it will be ignored.',
                'metadata': {'folder': dir_path}
            })
        )
        return None

    def __create_assets_from_metadata(self, assets_matadata, dir_path):
        '''Create assets object based on assets metadata.'''

        # search for all files that end with `.png`
        png_files = glob(f'{dir_path}/*.png')

        if not png_files:
            self.errors_insert.append(
                PostgreSQLPublisherConnection.create_task_error_insert_clause({
                    'type': 'warning',
                    'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                    'metadata': {'folder': dir_path}
                })
            )
            return None

        # initialize `assets` object with the `thumbnail` key
        assets = {
            'thumbnail': {
                'href': png_files[0],
                'type': 'image/png',
                'roles': ['thumbnail']
            }
        }

        for band, band_template in assets_matadata.items():
            # search for all TIFF files based on a template with `band_template`
            # for example: search all TIFF files that matches with '/folder/*BAND6.tif'
            tiff_files = sorted(glob(f'{dir_path}/*{band_template}'))

            if not tiff_files:
                # EVI and NDVI files are optional, then if they do not exist, do not report them
                if band == 'evi' or band == 'ndvi':
                    continue

                self.errors_insert.append(
                    PostgreSQLPublisherConnection.create_task_error_insert_clause({
                        'type': 'warning',
                        'message': ('There is NOT a TIFF file in this folder that ends with the '
                                    f'`{band_template}` template, then it will be ignored.'),
                        'metadata': {'folder': dir_path}
                    })
                )
                return None

            # get just the band name from the template (e.g. `BAND6`)
            band_name = band_template.replace('.tif', '')

            # add TIFF file as an asset
            assets[band_name] = {
                'href': tiff_files[0],
                'type': 'image/tiff; application=geotiff',
                'common_name': band,
                'roles': ['data']
            }

            # quality, evi and ndvi TIFF files have not XML files
            if band == 'quality' or band == 'evi' or band == 'ndvi':

                # `quality` band contains a JSON file
                if band == 'quality':
                    # search for all JSON files based on a template with `band_template`
                    # for example: search all JSON files that matches with '/folder/*BAND6.json'
                    json_files = sorted(glob(f"{dir_path}/*{band_template.replace('.tif', '.json')}"))

                    if not json_files:
                        self.errors_insert.append(
                            PostgreSQLPublisherConnection.create_task_error_insert_clause({
                                'type': 'warning',
                                'message': ('There is NOT a JSON file in this folder that ends with the '
                                            f"`{band_template.replace('.tif', '.json')}` template, "
                                            'then it will be ignored.'),
                                'metadata': {'folder': dir_path}
                            })
                        )
                        return None

                    # add XML file as an asset
                    assets[band_name + '_json'] = {
                        'href': json_files[0],
                        'type': 'application/json',
                        'roles': ['metadata']
                    }

                continue

            # search for all TIFF files based on a template with `band_template`
            # for example: search all TIFF files that matches with '/folder/*BAND6.xml'
            xml_files = sorted(glob(f"{dir_path}/*{band_template.replace('.tif', '.xml')}"))

            if not xml_files:
                self.errors_insert.append(
                    PostgreSQLPublisherConnection.create_task_error_insert_clause({
                        'type': 'warning',
                        'message': ('There is NOT a XML file in this folder that ends with the '
                                    f"`{band_template.replace('.tif', '.xml')}` template, "
                                    'then it will be ignored.'),
                        'metadata': {'folder': dir_path}
                    })
                )
                return None

            # add XML file as an asset
            assets[band_name + '_xml'] = {
                'href': xml_files[0],
                'type': 'application/xml',
                'roles': ['metadata']
            }

        return assets

    def __generator(self):
        '''Generator that returns just directories with valid files.'''

        for dir_path, dirs, files in walk(self.BASE_DIR):
            # if dir is not valid based on query, then ignore it
            is_dir_path_valid, satellite, sensor = self.__is_dir_path_valid(dir_path)
            if not is_dir_path_valid:
                continue

            # if the dir does not have any file, then report and ignore it
            if not files:
                self.errors_insert.append(
                    PostgreSQLPublisherConnection.create_task_error_insert_clause({
                        'message': 'This folder is valid, but it is empty.',
                        'metadata': {'folder': dir_path},
                        'type': 'warning'
                    })
                )
                continue

            # if there is not DN XML file, then ignore it
            dn_xml_file_path = self.__get_dn_xml_file_path(files, dir_path)
            if not dn_xml_file_path:
                continue

            assets = {}
            for radio_processing in self.query['radio_processing']:
                # if user is publishing `SR` files, but there is not any
                # `SR` files in this folder, then ignore it
                if radio_processing == 'SR' and not is_there_sr_files_in_the_list_of_files(files):
                    continue

                assets_metadata = self.satellite_metadata.get_assets_metadata(
                    satellite, sensor, radio_processing
                )

                # if there is not a valid asset, then ignore it
                __assets = self.__create_assets_from_metadata(assets_metadata, dir_path)
                if not __assets:
                    continue

                assets[radio_processing] = __assets

            # if there is not one asset at least, then ignore it
            if not assets:
                continue

            # yield just valid directories
            yield dir_path, dn_xml_file_path, assets

    def __iter__(self):
        # this method makes the class to be an iterable
        return self

    def __next__(self):
        # this method makes the class to be a generator
        return next(self.__generator_iterator)
