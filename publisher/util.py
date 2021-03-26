from copy import deepcopy
from datetime import datetime, timedelta
from glob import glob
from json import loads
from os import walk
from os.path import abspath, dirname, join as os_path_join, sep as os_path_sep
from re import search

from shapely.geometry import mapping
from xmltodict import parse as xmltodict_parse

from publisher.common import fill_string_with_left_zeros, print_line
from publisher.environment import PR_LOGGING_LEVEL
from publisher.exception import PublisherDecodeException
from publisher.logger import create_logger
from publisher.model import PostgreSQLCatalogTestConnection, PostgreSQLPublisherConnection
from publisher.utils.geom import raster_convexhull, raster_extent


# create logger object
logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


def convert_xml_to_dict(xml_path):
    '''Read an XML file, convert it to a dictionary and return it.'''

    with open(xml_path, 'r') as data:
        return xmltodict_parse(data.read())


##################################################
# Item
##################################################

def get_xml_as_dict_from_xml_path(xml_path):
    xml_as_dict = convert_xml_to_dict(xml_path)

    # logger.info(f'get_xml_as_dict_from_xml_path - xml_path: {xml_path}')

    # 'prdf' - DN file; and 'rpdf' - SR file
    if 'prdf' not in xml_as_dict and 'rpdf' not in xml_as_dict:
        return None

    if 'prdf' in xml_as_dict:
        xml_as_dict = xml_as_dict['prdf']

        if 'leftCamera' in xml_as_dict:
            xml_as_dict = xml_as_dict['leftCamera']

        xml_as_dict['datetime'] = xml_as_dict['viewing']['center'][0:19]
        xml_as_dict['sun_position'] = dict(xml_as_dict['image']['sunPosition'])
        # rename key from 'sunAzimuth' to 'azimuth'
        xml_as_dict['sun_position']['azimuth'] = xml_as_dict['sun_position'].pop('sunAzimuth')
        xml_as_dict['sync_loss'] = None  # default value

        # if there is sync loss inside the XML, then get it
        if 'syncLoss' in xml_as_dict['image']:
            sync_loss_bands = xml_as_dict['image']['syncLoss']['band']
            # get the max value from the sync losses
            xml_as_dict['sync_loss'] = max([
                float(sync_loss_band['#text']) for sync_loss_band in sync_loss_bands
            ])

    elif 'rpdf' in xml_as_dict:
        xml_as_dict = xml_as_dict['rpdf']

        if 'leftCamera' in xml_as_dict:
            xml_as_dict = xml_as_dict['leftCamera']

        xml_as_dict['datetime'] = xml_as_dict['sceneInfo']['centerTime'][0:19]
        xml_as_dict['sun_position'] = dict(xml_as_dict['sunPosition'])
        # default 'azimuth' field to SR scene is right, then I do not need to rename it
        xml_as_dict['sync_loss'] = None

    # convert values to float
    for key in xml_as_dict['sun_position']:
        xml_as_dict['sun_position'][key] = float(xml_as_dict['sun_position'][key])

    return xml_as_dict


def get_item_collection(metadata, radio_processing):
    '''Get collection information from parameters.'''

    collection = {
        'satellite': metadata['satellite'],
        'sensor': metadata['sensor'],
        # geometric processing: L2, L4, etc.
        'geo_processing': metadata['geo_processing'],
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


def get_item_properties(xml_path, metadata, collection):
    '''Get properties information from parameters.'''

    xml_as_dict = get_xml_as_dict_from_xml_path(xml_path)

    # get the item's properties
    properties = {
        # get just the date and time of the string
        'datetime': xml_as_dict['datetime'],
        # convert path and row from string to integer
        'path': int(metadata['path']),
        'row': int(metadata['row']),
        'satellite': collection['satellite'],
        'sensor': collection['sensor'],
        'sun_position': xml_as_dict['sun_position'],
        'sync_loss': xml_as_dict['sync_loss'],
        # CQ fills it
        # 'cloud_cover': '',
        # 'deleted': item['deleted'],
    }

    # create item name based on its properties (e.g. `CBERS4A_MUX_070122_20200813`)
    properties['name'] = (
        f"{collection['satellite']}_{collection['sensor']}_"
        # fill path and row with left zeros in order to create the item name
        f"{fill_string_with_left_zeros(str(properties['path']))}"
        f"{fill_string_with_left_zeros(str(properties['row']))}_"
        f"{properties['datetime'].split('T')[0].replace('-', '')}_"
        f"L{collection['geo_processing']}_{collection['radio_processing']}"
    )

    return properties


def get_geometry_from_tiff(tiff_path, epsg=4326):
    '''Get TIFF extent from the TIFF path.'''

    tiff_extent = raster_extent(tiff_path)

    geojson = mapping(tiff_extent)
    geojson['crs'] = {'type': 'name','properties': {'name': f'EPSG:{epsg}'}}

    # return a GeoJSON from TIFF extent
    return geojson


def get_convex_hull_from_tiff(tiff_path, epsg=4326):
    '''Get TIFF convex hull from the TIFF path.'''

    tiff_convex_hull = raster_convexhull(tiff_path)

    geojson = mapping(tiff_convex_hull)
    geojson['crs'] = {'type': 'name','properties': {'name': f'EPSG:{epsg}'}}

    # return a GeoJSON from TIFF convex hull
    return geojson


def get_file_path_from_assets(assets, file_type='tiff'):
    '''Returns the first band TIFF file path that is found inside `assets` dictionary.'''

    if file_type == 'xml':
        for k, v in assets.items():
            # search the first XML file without `RIGHT` and `LEFT` strings
            if file_type in v['type']:
                xml_path = v['href']
                if 'BAND' in xml_path and 'RIGHT' not in xml_path \
                        and 'LEFT' not in xml_path:
                    return  xml_path
    # else, if there are just files with `RIGHT` and `LEFT` string,
    # then return it in the next loop

    for k, v in assets.items():
        # check if the asset is a band TIFF file
        if file_type in v['type'] and 'BAND' in v['href']:
            # return the first one path that is found
            return  v['href']

    return None


def create_items(metadata, assets):
    '''
    Return a list of items based on an XML file as dictionary and the
    radiometric processing information the user chose.
    '''

    # if user chose `DN` and `SR` radiometric processings, then create both items
    if 'DN' in assets and 'SR' in assets:
        ##################################################
        # create DN item
        ##################################################
        dn_item = {'collection': get_item_collection(metadata, 'DN')}

        # get one XML path to extract extra metadata
        xml_path = get_file_path_from_assets(assets['DN'], file_type='xml')
        dn_item['properties'] = get_item_properties(xml_path, metadata, dn_item['collection'])

        # get one TIFF path in order to extract the geometry and convex_hull
        tiff_path = get_file_path_from_assets(assets['DN'])
        dn_item['geometry'] = get_geometry_from_tiff(tiff_path)
        # dn_item['convex_hull'] = get_convex_hull_from_tiff(tiff_path)

        ##################################################
        # create SR item based on DN item, because they have almost the same information
        ##################################################
        # the only different information they have is the radiometric processing
        sr_item = deepcopy(dn_item)
        sr_item['collection']['radio_processing'] = 'SR'
        sr_item['collection']['name'] = sr_item['collection']['name'].replace('DN', 'SR')
        sr_item['collection']['description'] = sr_item['collection']['description'].replace('DN', 'SR')
        sr_item['properties']['name'] = sr_item['properties']['name'].replace('DN', 'SR')

        ##################################################
        # add the correct asset to each item
        ##################################################
        dn_item['assets'] = assets['DN']
        sr_item['assets'] = assets['SR']

        # return both `DN` and `SR` items
        return [dn_item, sr_item]

    # if user chose just `DN` radiometric processing, create a collection with it
    if 'DN' in assets:
        item = {
            'collection': get_item_collection(metadata, 'DN'),
            'assets': assets['DN']
        }

    # if user chose just `SR` radiometric processing, create a collection with it
    elif 'SR' in assets:
        item = {
            'collection': get_item_collection(metadata, 'SR'),
            'assets': assets['SR']
        }

    # get one XML path to extract extra metadata
    xml_path = get_file_path_from_assets(item['assets'], file_type='xml')
    item['properties'] = get_item_properties(xml_path, metadata, item['collection'])

    # get one TIFF path in order to extract the geometry and convex_hull
    tiff_path = get_file_path_from_assets(item['assets'])
    item['geometry'] = get_geometry_from_tiff(tiff_path)
    # item['convex_hull'] = get_convex_hull_from_tiff(tiff_path)

    # return either `DN` or `SR` item
    return [item]


def create_item_and_get_insert_clauses(dir_path, metadata, assets, df_collections):
    print_line()

    items_insert = []
    errors_insert = []

    logger.info(f'dir_path: {dir_path}')
    logger.info(f'metadata: {metadata}')
    # logger.info(f'assets: {assets}')

    # `items` is a list of items (e.g. [dn_item, sr_item])
    items = create_items(metadata, assets)
    # logger.info(f'items size: {len(items)}\n')

    for item in items:
        print_line()
        # logger.info(f'item: {item}\n')
        logger.info(f"item[properties]: {item['properties']}")
        logger.info(f"item[collection]: {item['collection']}")

        # get collection id from dataframe
        collection = df_collections.loc[
            df_collections['name'] == item['collection']['name']
        ].reset_index(drop=True)
        # logger.info(f'collection:\n{collection}')

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
                        'metadata': {'folder': dir_path},
                        'type': 'warning'
                    })
                )
            continue

        collection_id = collection.at[0, 'id']
        # logger.info(f'collection_id: {collection_id}')

        # create INSERT clause based on item metadata
        insert = PostgreSQLCatalogTestConnection.create_item_insert_clause(
            item, collection_id
        )
        # logger.info(f'insert: {insert}\n')
        logger.info(f"Adding an INSERT clause to `{item['properties']['name']}` "
                     "item in the list...\n")
        items_insert.append(insert)

    return items_insert, errors_insert


##################################################
# Generator
##################################################


def decode_scene_dir(scene_dir):
    '''Decode a scene directory, returning its information.'''

    scene_dir_first, scene_dir_second = scene_dir.split('.')

    if scene_dir_first.startswith('AMAZONIA_1') or scene_dir_first.startswith('CBERS_4'):
        # examples:
        # - AMAZONIA_1_WFI_DRD_2021_03_03.12_57_40_CB11
        # - AMAZONIA_1_WFI_DRD_2021_03_03.14_35_23_CB11_SIR18
        # - CBERS_4_MUX_DRD_2020_07_31.13_07_00_CB11
        # - CBERS_4A_MUX_RAW_2019_12_27.13_53_00_ETC2
        # - CBERS_4A_MUX_RAW_2019_12_28.14_15_00

        satellite, number, sensor, _, *date = scene_dir_first.split('_')
        # create satellite name with its number
        satellite = satellite + number
        date = '-'.join(date)
        time = scene_dir_second.split('_')

        if len(time) >= 3:
            # get the time part from the list of parts
            # `time` can be: `13_53_00`, `13_53_00_ETC2`, `14_35_23_CB11_SIR18`, etc.
            time = ':'.join(time[0:3])
        else:
            raise PublisherDecodeException()

    elif scene_dir_first.startswith('CBERS2B') or scene_dir_first.startswith('LANDSAT'):
        # examples: CBERS2B_CCD_20070925.145654
        # or LANDSAT1_MSS_19750907.130000

        satellite, sensor, date = scene_dir_first.split('_')
        time = scene_dir_second

        if len(date) != 8:
            # example: a time should be something like this: '20070925'
            raise PublisherDecodeException()

        # I build the date string based on the old one (e.g. from '20070925' to '2007-09-25')
        date = f'{date[0:4]}-{date[4:6]}-{date[6:8]}'

        if len(time) != 6:
            # example: a time should be something like this: '145654'
            raise PublisherDecodeException()

        # I build the time string based on the old one (e.g. from '145654' to '14:56:54')
        time = f'{time[0:2]}:{time[2:4]}:{time[4:6]}'

    else:
        raise PublisherDecodeException(f'Scene directory cannot be decoded: `{scene_dir}`.')

    return satellite, sensor, date, time


def decode_path_row_dir(path_row_dir):
    splitted_path_row = path_row_dir.split('_')

    if len(splitted_path_row) == 3:
        # example: `151_098_0`
        path, row, _ = splitted_path_row
    elif len(splitted_path_row) == 5:
        # example: `151_B_141_5_0`
        path, _, row, *_ = splitted_path_row
    else:
        raise PublisherDecodeException(f'Path/row directory cannot be decoded: `{path_row_dir}`.')

    return path, row


def decode_geo_processing_dir(geo_processing_dir):
    geo_processing = geo_processing_dir.split('_')[0]

    if geo_processing == '2' or geo_processing == '2B' or geo_processing == '3' or geo_processing == '4':
        return geo_processing

    raise PublisherDecodeException(f'Geo. processing directory cannot be decoded: `{geo_processing_dir}`.')


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

    def __get_metadata_from_splitted_dir_path(self, splitted_dir_path):
        # add the metadata based on the directory decode
        metadata = {}

        # extract `satellite` and `sensor` data from path
        _, metadata['satellite'], _, scene_dir, path_row_dir, geo_processing_dir = splitted_dir_path

        try:
            _, metadata['sensor'], *_ = decode_scene_dir(scene_dir)
            metadata['path'], metadata['row'] = decode_path_row_dir(path_row_dir)
            metadata['geo_processing'] = decode_geo_processing_dir(geo_processing_dir)
        except PublisherDecodeException as error:
            self.errors_insert.append(
                PostgreSQLPublisherConnection.create_task_error_insert_clause({
                    'message': error,
                    'metadata': {'folder': dir_path, 'method': '__get_metadata_from_splitted_dir_path'},
                    'type': 'error'
                })
            )
            return None

        return metadata

    def __create_assets_from_metadata(self, assets_matadata, dir_path):
        '''Create assets object based on assets metadata.'''

        # search for all files that end with `.png`
        png_files = glob(f'{dir_path}/*.png')

        if not png_files:
            self.errors_insert.append(
                PostgreSQLPublisherConnection.create_task_error_insert_clause({
                    'message': 'There is NOT a quicklook in this folder, then it will be ignored.',
                    'metadata': {'folder': dir_path},
                    'type': 'warning'
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
                        'message': ('There is NOT a TIFF file in this folder that ends with the '
                                    f'`{band_template}` template, then it will be ignored.'),
                        'metadata': {'folder': dir_path},
                        'type': 'warning'
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
                        'message': ('There is NOT an XML file in this folder that ends with the '
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

    def __filter_dir(self, dir_level, dir_path, dirs):
        '''Filter `dirs` parameter based on the directory level.'''

        # check the year_month dirs
        if dir_level == 2:
            # I'm inside satellite folder, then the dirs are year-month folders
            # return just the year_month dirs that are between the date range
            # `start_date` and `end_date` fields are required

            # example: 2019_01
            start_year_month = (f"{self.query['start_date'].year}_"
                                f"{fill_string_with_left_zeros(str(self.query['start_date'].month), 2)}")
            # example: 2020_12
            end_year_month = (f"{self.query['end_date'].year}_"
                              f"{fill_string_with_left_zeros(str(self.query['end_date'].month), 2)}")

            return [d for d in dirs if d >= start_year_month and d <= end_year_month]

        # check the scene dirs
        elif dir_level == 3:
            # I'm inside year-month folder, then the dirs are scene folders
            # return just the scene dirs that have the selected sensor

            # if the option is None, then return the original dirs
            if self.query['sensor'] is None:
                return dirs

            def check_scene_dir(scene_dir):
                try:
                    _, sensor_dir, date_dir, time_dir = decode_scene_dir(scene_dir)
                except PublisherDecodeException as error:
                    self.errors_insert.append(
                        PostgreSQLPublisherConnection.create_task_error_insert_clause({
                            'message': error,
                            'metadata': {'folder': dir_path, 'method': 'check_scene_dir'},
                            'type': 'warning'
                        })
                    )
                    return None

                # if scene_dir does not have the selected sensor, then not return it
                if sensor_dir != self.query['sensor']:
                    return None

                # convert date from str to datetime
                date = datetime.strptime(date_dir, '%Y-%m-%d')

                # if time dir is between 0h and 5h, then consider it one day ago,
                # because date is reception date and not viewing date
                if time_dir >= '00:00:00' and time_dir <= '05:00:00':
                    # subtract one day from the date
                    date -= timedelta(days=1)

                # if scene_dir is not inside the selected date range, then not return it
                if not (date >= self.query['start_date'] and date <= self.query['end_date']):
                    return None

                return scene_dir

            return list(filter(check_scene_dir, dirs))

        # check the path/row dirs
        elif dir_level == 4:
            # I'm inside sensor folder, then the dirs are path/row folders

            def check_path_row_dir(path_row_dir):
                try:
                    path, row = decode_path_row_dir(path_row_dir)
                except PublisherDecodeException as error:
                    self.errors_insert.append(
                        PostgreSQLPublisherConnection.create_task_error_insert_clause({
                            'message': error,
                            'metadata': {'folder': dir_path, 'method': 'check_path_row_dir'},
                            'type': 'warning'
                        })
                    )
                    return None

                if self.query['path'] is not None and self.query['path'] != int(path):
                    return None

                if self.query['row'] is not None and self.query['row'] != int(row):
                    return None

                return path_row_dir

            return list(filter(check_path_row_dir, dirs))

        # check the geo processing dirs
        elif dir_level == 5:
            # I'm inside path/row folder, then the dirs are geo processing folders

            # lambda function to check if the directory starts with any selected geo processing
            check_if_dir_startswith_any_gp = lambda directory: any(
                directory.startswith(gp) for gp in self.query['geo_processing']
            )

            # if the level_dir does not start with the informed geo_processing, then the folder is invalid
            # `d` example: `2_BC_UTM_WGS84`
            return [d for d in dirs if check_if_dir_startswith_any_gp(d)]

        # check files existence
        elif dir_level == 6:
            # I'm inside geo processing folder, then should not have dirs inside here

            if dirs:
                self.errors_insert.append(
                    PostgreSQLPublisherConnection.create_task_error_insert_clause({
                        'message': 'There are folders inside a geo processing directory.',
                        'metadata': {'folder': dir_path},
                        'type': 'warning'
                    })
                )

            return dirs

        self.errors_insert.append(
            PostgreSQLPublisherConnection.create_task_error_insert_clause({
                'message': f'Invalid `{dir_level}` directory level.',
                'metadata': {'folder': dir_path},
                'type': 'warning'
            })
        )

        return dirs

    def __generator(self):
        '''Generator that returns just directories with valid files.'''

        # logger.info('PublisherWalk\n')

        # `base_path` example: /TIFF/CBERS2B/
        base_path = f'{self.BASE_DIR}/{self.query["satellite"]}'

        # logger.info(f'PublisherWalk - self.query: {self.query}')

        for dir_path, dirs, files in walk(base_path):
            # get dir path starting at `/TIFF`
            index = dir_path.find('TIFF')
            # `splitted_dir_path` example:
            # ['TIFF', 'CBERS4A', '2020_11', 'CBERS_4A_WFI_RAW_2020_11_10.13_41_00_ETC2',
            #  '207_148_0', '2_BC_UTM_WGS84']
            splitted_dir_path = dir_path[index:].split(os_path_sep)
            dir_level = len(splitted_dir_path)

            # get just the valid dirs and replace old ones with them
            dirs[:] = self.__filter_dir(dir_level, dir_path, dirs)

            # if I'm not inside a geo processing dir, then ignore this folder
            if dir_level != 6:
                continue

            # if the dir does not have any file, then report and ignore this folder
            if not files:
                self.errors_insert.append(
                    PostgreSQLPublisherConnection.create_task_error_insert_clause({
                        'message': 'This folder is valid, but it is empty.',
                        'metadata': {'folder': dir_path},
                        'type': 'warning'
                    })
                )
                continue

            # if there are not enough metadata, then ignore this folder
            metadata = self.__get_metadata_from_splitted_dir_path(splitted_dir_path)
            if not metadata:
                continue

            assets = {}
            for radio_processing in self.query['radio_processing']:
                # if user is publishing `SR` files, but there is not any
                # `SR` files in this folder, then ignore it
                if radio_processing == 'SR' and not is_there_sr_files_in_the_list_of_files(files):
                    continue

                assets_metadata = self.satellite_metadata.get_assets_metadata(
                    metadata['satellite'], metadata['sensor'], radio_processing
                )

                # if there is not a valid asset, then ignore it
                __assets = self.__create_assets_from_metadata(assets_metadata, dir_path)
                if not __assets:
                    continue

                assets[radio_processing] = __assets

            # if there is not one asset at least, then ignore this folder
            if not assets:
                continue

            # yield just valid directories
            yield dir_path, metadata, assets

    def __iter__(self):
        # this method makes the class to be an iterable
        return self

    def __next__(self):
        # this method makes the class to be a generator
        return next(self.__generator_iterator)

    def save_the_errors_in_the_database(self):
        # if there are INSERT clauses, then insert them in the database
        if self.errors_insert:
            # if there is INSERT clauses to insert in the database,
            # then create a database instance and insert them there
            db = PostgreSQLPublisherConnection()
            concanate_errors = ' '.join(self.errors_insert)
            # logger.info(f'concanate_errors: \n{concanate_errors}\n')
            logger.info('Inserting PublisherWalk.errors into database...')
            db.execute(concanate_errors, is_transaction=True)


##################################################
# Other
##################################################

class SatelliteMetadata:

    def __init__(self):
        self.SATELLITES = None

        # read satellites metadata file
        self.__read_metadata_file()

    def __read_metadata_file(self):
        '''Read JSON satellite metadata file.'''

        # dirname(abspath(__file__)): project's root directory
        satellites_path = os_path_join(dirname(abspath(__file__)), 'metadata', 'satellites.json')

        with open(satellites_path, 'r') as data:
            # read JSON file and convert it to dict
            self.SATELLITES = loads(data.read())

    def get_assets_metadata(self, satellite=None, sensor=None, radio_processing=None, **kwargs):
        '''Get assets metadata based on the parameters.'''

        # get the satellite information
        satellite = list(filter(lambda s: s['name'] == satellite, self.SATELLITES['satellites']))

        # if a satellite has not been found, then return None
        if not satellite:
            return None

        # if a satellite has been found, then get the unique value inside the list
        # and get the sensor information
        sensor = list(filter(lambda s: s['name'] == sensor, satellite[0]['sensors']))

        # if a sensor has not been found, then return None
        if not sensor:
            return None

        # if a sensor has been found, then get the unique value inside the list
        # and return assets metadata based on the radiometric processing (i.e. DN or SR)
        return  sensor[0]['assets'][radio_processing]
