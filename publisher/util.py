from copy import deepcopy
from datetime import datetime, timedelta
from glob import glob
from json import dumps
from os import walk
from os.path import join as os_path_join, sep as os_path_sep
from re import search

from werkzeug.exceptions import InternalServerError
from xmltodict import parse as xmltodict_parse


def convert_xml_to_dict(xml_path):
    '''Read an XML file, convert it to a dictionary and return it.'''

    with open(xml_path, 'r') as data:
        return xmltodict_parse(data.read())


##################################################
# Item
##################################################

def create_insert_clause(item, collection_id, srid=4326):
    '''Create `INSERT` clause based on item metadata.'''

    min_x = item['bbox'][0]
    min_y = item['bbox'][1]
    max_x = item['bbox'][2]
    max_y = item['bbox'][3]

    properties = item['properties']
    datetime = properties['datetime']

    return (
        # delete old item before adding a new one, if it exists
        f'DELETE FROM bdc.items WHERE name=\'{properties["name"]}\'; '
        # insert new item
        'INSERT INTO bdc.items '
        '(name, collection_id, start_date, end_date, '
        'cloud_cover, assets, metadata, geom, min_convex_hull, srid) '
        'VALUES '
        f'(\'{properties["name"]}\', {collection_id}, \'{datetime}\', \'{datetime}\', '
        f'NULL, \'{dumps(item["assets"])}\', \'{dumps(properties)}\', '
        f'ST_GeomFromGeoJSON(\'{dumps(item["geometry"])}\'), '
        f'ST_MakeEnvelope({min_x}, {min_y}, {max_x}, {max_y}, {srid}), {srid});'
    )


def create_assets_from_metadata(assets_matadata, dir_path):
    '''Create assets object based on assets metadata.'''

    assets = {}

    # create a shortened path starting on `/TIFF`
    # index = dir_path.find('/TIFF')
    # shortened_dir_path = dir_path[index:]

    for band, band_template in assets_matadata.items():
        # search for all TIFF files based on a template with `band_template`
        # for example: search all TIFF files that matched with '/folder/*BAND6.tif'
        tiff_files = glob(f'{dir_path}/*{band_template}')

        if tiff_files:
            # get just the band name from the template (e.g. `BAND6`)
            band_name = band_template.replace('.tif', '')

            # add TIFF file as an asset
            assets[band_name] = {
                # 'href': os_path_join(shortened_dir_path, tiff_files[0]),
                'href': tiff_files[0],
                'type': 'image/tiff; application=geotiff',
                'common_name': band,
                'roles': ['data']
            }

            # add XML file as an asset
            assets[band_name + '_xml'] = {
                # 'href': os_path_join(shortened_dir_path, tiff_files[0].replace('.tif', '.xml')),
                'href': tiff_files[0].replace('.tif', '.xml'),
                'type': 'application/xml',
                'roles': ['metadata']
            }

    # search for all files that end with `.png`
    png_files = glob(f'{dir_path}/*.png')

    if png_files:
        assets['thumbnail'] = {
            # 'href': os_path_join(shortened_dir_path, png_files[0]),
            'href': png_files[0],
            'type': 'image/png',
            'roles': ['thumbnail']
        }

    return assets


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
        'path': int(xml_as_dict['image']['path']),
        'row': int(xml_as_dict['image']['row']),
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


def create_items_from_xml_as_dict(xml_as_dict, radio_processing_list):
    '''
    Return a list of items based on an XML file as dictionary and the
    radiometric processing information the user chose.
    '''

    # if user chose `DN` and `SR` radiometric processings, then create both items
    if 'DN' in radio_processing_list and 'SR' in radio_processing_list:
        # create DN item
        dn_item = {}
        dn_item['collection'] = get_collection_from_xml_as_dict(xml_as_dict, 'DN')
        dn_item['properties'] = get_properties_from_xml_as_dict(xml_as_dict, dn_item['collection'])
        dn_item['bbox'] = get_bbox_from_xml_as_dict(xml_as_dict)
        dn_item['geometry'] = get_geometry_from_xml_as_dict(xml_as_dict)

        # create SR item from DN item, because they have almost the same information
        # the only different information they have is the radiometric processing
        sr_item = deepcopy(dn_item)
        sr_item['collection']['radio_processing'] = 'SR'
        sr_item['collection']['name'] = sr_item['collection']['name'].replace('DN', 'SR')
        sr_item['collection']['description'] = sr_item['collection']['description'].replace('DN', 'SR')
        sr_item['properties']['name'] = sr_item['properties']['name'].replace('DN', 'SR')

        # return both `DN` and `SR` items
        return [dn_item, sr_item]

    # if user chose just `DN` radiometric processing, create a collection with it
    if 'DN' in radio_processing_list:
        item = {
            'collection': get_collection_from_xml_as_dict(xml_as_dict, 'DN')
        }

    # if user chose just `SR` radiometric processing, create a collection with it
    elif 'SR' in radio_processing_list:
        item = {
            'collection': get_collection_from_xml_as_dict(xml_as_dict, 'SR')
        }

    # extract other information to the item
    item['properties'] = get_properties_from_xml_as_dict(xml_as_dict, item['collection'])
    item['bbox'] = get_bbox_from_xml_as_dict(xml_as_dict)
    item['geometry'] = get_geometry_from_xml_as_dict(xml_as_dict)

    # return either `DN` or `SR` item
    return [item]


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


def get_dn_files_as_dicts_from_files(files, dir_path):
    # example: CBERS_4_AWFI_20201228_157_135_L4_RIGHT_BAND16.xml
    dn_template = '^[a-zA-Z0-9_]+BAND\d+.xml'

    # get just the DN XML files based on the radiometric processing regex
    # for both DN or SR files, I extract information from a DN XML file
    dn_xml_files = list(filter(lambda f: search(dn_template, f), files))

    if dn_xml_files:
        # `dn_xml_files[0]` gets the first DN XML file
        # `os_path_join` creates a full path to the XML file
        # `convert_xml_to_dict` converts XML file to dict object
        xml_as_dict = convert_xml_to_dict(os_path_join(dir_path, dn_xml_files[0]))

        # check if there is `DN` information in the XML file
        if 'prdf' in xml_as_dict:
            return xml_as_dict['prdf']

    return None


def get_sr_files_as_dicts_from_files(files):
    # example: CBERS_4_AWFI_20201228_157_135_L4_BAND16_GRID_SURFACE.xml
    sr_template = '^[a-zA-Z0-9_]+BAND\d+_GRID_SURFACE.xml'

    # get just the SR XML files based on the radiometric processing regex
    sr_xml_files = list(filter(lambda f: search(sr_template, f), files))

    return sr_xml_files if sr_xml_files else None


class PublisherWalk:
    '''This class is a Generator that encapsulates `os.walk()` generator to return just valid directories.
    A valid directory is a folder that contains XML files.'''

    def __init__(self, BASE_DIR, query=None):
        self.BASE_DIR = BASE_DIR
        self.query = query
        self.errors = []

        # create an iterator from generator method
        self.__generator_iterator = self.__generator()

    def __is_dir_path_valid(self, dir_path):
        '''Check if `dir_path` parameter is valid based on `query`.'''

        # get dir path starting at `/TIFF`
        index = dir_path.find('TIFF')
        splitted_dir_path = dir_path[index:].split(os_path_sep)

        # a valid dir path must have at least five folders (+1 the base path (i.e. /TIFF))
        if len(splitted_dir_path) < 6:
            return False

        _, satellite_dir, year_month_dir, scene_dir, path_row_dir, level_dir = splitted_dir_path

        # if the informed satellite is not equal to the dir, then the folder is invalid
        if self.query['satellite'] is not None and self.query['satellite'] != satellite_dir:
            return False

        _, sensor, date, time = decode_scene_dir(scene_dir)

        # if the informed sensor is not equal to the dir, then the folder is invalid
        if self.query['sensor'] is not None and self.query['sensor'] != sensor:
            return False

        # if the actual dir is not inside the date range, then the folder is invalid
        if self.query['start_date'] is not None and self.query['end_date'] is not None:
            # convert date from str to datetime
            date = datetime.strptime(date, '%Y-%m-%d')

            # if time dir is between 0h and 5h, then consider it one day ago,
            # because date is reception date and not viewing date
            if time >= '00:00:00' and time <= '05:00:00':
                # subtract one day from the date
                date -= timedelta(days=1)

            if not (date >= self.query['start_date'] and date <= self.query['end_date']):
                return False

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
                return False

            if self.query['row'] is not None and self.query['row'] != int(row):
                return False

        # if the level_dir does not start with the informed geo_processing, then the folder is invalid
        if self.query['geo_processing'] is not None and not level_dir.startswith(str(self.query['geo_processing'])):
            # example: `2_BC_UTM_WGS84`
            return False

        return True

    def __get_dn_xml_file(self, files, dir_path):
        '''Return just one DN XML file inside the directory as a dictionary.'''

        radio_processing = self.query['radio_processing']

        # if radio_processing is not DN, SR or None, then it is invalid
        if radio_processing == 'DN':
            # user chose to publish just `DN` files
            return get_dn_files_as_dicts_from_files(files, dir_path), ['DN']

        elif radio_processing == 'SR':
            # user chose to publish just `SR` files
            sr_xml_files = get_sr_files_as_dicts_from_files(files)

            # if there are SR files, then I will extract the information from the DN file
            if sr_xml_files:
                return get_dn_files_as_dicts_from_files(files, dir_path), ['SR']

        elif radio_processing is None:
            # user chose to publish bothm `DN` and `SR` files
            sr_xml_files = get_sr_files_as_dicts_from_files(files)
            dn_xml_files = get_dn_files_as_dicts_from_files(files, dir_path)

            # if there are both DN and SR files, then I will publish
            # information from both radiometric processings
            if dn_xml_files and sr_xml_files:
                return dn_xml_files, ['DN', 'SR']

            # if there are just DN files, then I will publish information
            # from the DN radiometric processing
            elif dn_xml_files and not sr_xml_files:
                return dn_xml_files, ['DN']

            else: # elif (not dn_xml_files and sr_xml_files) or (not dn_xml_files and not sr_xml_files):
                # if there is NOT DN XML files in the folder, then I save the error
                self.errors.append(
                    {
                        'type': 'warning',
                        'message': 'There is NOT a DN XML file in this folder.',
                        'metadata': {
                            'folder': dir_path
                        }
                    }
                )

                return None, []

        raise InternalServerError(f'Invalid radiometric processing: {radio_processing}')

    def __generator(self):
        '''Generator that returns just directories with valid files.'''

        for dir_path, dirs, files in walk(self.BASE_DIR):
            # if the dir does not have any file, then ignore it
            if not files:
                continue

            # if dir is not valid based on query, then ignore it
            if not self.__is_dir_path_valid(dir_path):
                continue

            # if a valid dir does not have files, then ignore it
            xml_as_dict, radio_processing_list = self.__get_dn_xml_file(files, dir_path)
            if not xml_as_dict:
                continue

            # yield just valid directories
            yield dir_path, xml_as_dict, radio_processing_list

    def __iter__(self):
        # this method makes the class to be an iterable
        return self

    def __next__(self):
        # this method makes the class to be a generator
        return next(self.__generator_iterator)
