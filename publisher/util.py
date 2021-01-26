from glob import glob
from json import dumps
from os import walk
from os.path import join

from xmltodict import parse as xmltodict_parse

from publisher.common import fill_string_with_left_zeros


def get_dict_from_xml_file(xml_path):
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
        'INSERT INTO bdc.items '
        '(name, collection_id, start_date, end_date, '
        'cloud_cover, assets, metadata, geom, min_convex_hull, srid) '
        'VALUES '
        f'(\'{properties["name"]}\', {collection_id}, \'{datetime}\', \'{datetime}\', '
        f'NULL, \'{dumps(item["assets"])}\', \'{dumps(properties)}\', '
        f'ST_GeomFromGeoJSON(\'{dumps(item["geometry"])}\'), '
        f'ST_MakeEnvelope({min_x}, {min_y}, {max_x}, {max_y}, {srid}), {srid}); '
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
                # 'href': join(shortened_dir_path, tiff_files[0]),
                'href': tiff_files[0],
                'type': 'image/tiff; application=geotiff',
                'common_name': band,
                'roles': ['data']
            }

            # add XML file as an asset
            assets[band_name + '_xml'] = {
                # 'href': join(shortened_dir_path, tiff_files[0].replace('.tif', '.xml')),
                'href': tiff_files[0].replace('.tif', '.xml'),
                'type': 'application/xml',
                'roles': ['metadata']
            }

    # search for all files that end with `.png`
    png_files = glob(f'{dir_path}/*.png')

    if png_files:
        assets['thumbnail'] = {
            # 'href': join(shortened_dir_path, png_files[0]),
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
        'path': fill_string_with_left_zeros(xml_as_dict['image']['path']),
        'row': fill_string_with_left_zeros(xml_as_dict['image']['row']),
        # CQ fills it
        # 'cloud_cover': '',
        'satellite': collection['satellite'],
        'sensor': collection['sensor'],
        # TODO: get sync_loss
        # 'sync_loss': item['sync_loss'],
        # 'deleted': item['deleted']
    }

    # create item name based on its properties (e.g. `CBERS4A_MUX_070122_20200813`)
    properties['name'] = (
        f"{collection['satellite']}_{collection['sensor']}_"
        f"{properties['path']}{properties['row']}_"
        f"{properties['datetime'].split('T')[0].replace('-', '')}"
    )

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


def get_geometry_from_xml_as_dict(xml_as_dict):
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
        # 'crs': {'type': 'name','properties': {'name': 'EPSG:4326'}}
    }


def get_dn_item_from_xml_as_dict(xml_as_dict, radio_processing='DN'):
    '''Get Item from an XML file as dictionary.'''

    item = {}

    item['collection'] = get_collection_from_xml_as_dict(xml_as_dict, radio_processing)
    item['properties'] = get_properties_from_xml_as_dict(xml_as_dict, item['collection'])
    item['bbox'] = get_bbox_from_xml_as_dict(xml_as_dict)
    item['geometry'] = get_geometry_from_xml_as_dict(xml_as_dict)

    return item


def create_item_from_xml_as_dict(xml_as_dict):
    '''Get Item from an XML file as dictionary.'''

    # if there is `DN` information in the XML file
    if 'prdf' in xml_as_dict:
        return get_dn_item_from_xml_as_dict(xml_as_dict['prdf'], radio_processing='DN')

    return None


##################################################
# Generator
##################################################

class PublisherWalk:
    '''This class is a Generator that encapsulates `os.walk()` generator to return just valid directories.
    A valid directory is a folder that contains XML files.'''

    def __init__(self, BASE_DIR):
        self.BASE_DIR = BASE_DIR
        self.errors = []

        # create an iterator from generator method
        self.__generator_iterator = self.__generator()

    def __get_xml_files(self, files, dir_path):
        '''Return just XML files.'''

        # get just the XML files
        xml_files = list(filter(lambda f: f.endswith('.xml'), files))

        # if there are NOT valid XML files, then I save the error
        if not xml_files:
            self.errors.append(
                {
                    'type': 'warning',
                    'message': 'There are NOT XML files in this folder.',
                    'metadata': {
                        'folder': dir_path
                    }
                }
            )
            return None

        return xml_files

    def __generator(self):
        '''Generator that returns just directories with valid files.'''

        for dir_path, dirs, files in walk(self.BASE_DIR):
            # folders that end with '_BC_UTM_WGS84' suffix are folders that should have files.
            # other folders I can ignore, because I don't expect to have any files in them.
            if not dir_path.endswith('_BC_UTM_WGS84'):
                continue

            xml_files = self.__get_xml_files(files, dir_path)
            if not xml_files:
                continue

            # yield just valid directories
            yield dir_path, dirs, xml_files

    def __iter__(self):
        # this method makes the class to be an iterable
        return self

    def __next__(self):
        # this method makes the class to be a generator
        return next(self.__generator_iterator)


##################################################
# Other
##################################################

def str2bool(value):
    # Source: https://stackoverflow.com/a/715468
    return str(value).lower() in ('true', 't', '1', 'yes', 'y')
