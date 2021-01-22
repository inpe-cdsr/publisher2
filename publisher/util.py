from xmltodict import parse as xmltodict_parse

from publisher.common import fill_string_with_left_zeros


def get_dict_from_xml_file(xml_path):
    '''Read an XML fil, convert it to a dictionary and return it.'''

    with open(xml_path, 'r') as data:
        return xmltodict_parse(data.read())


def get_collection_from_xml_as_dict(xml_as_dict, radio_processing):
    '''Get collection information from XML file as dictionary.'''

    collection = {
        'satellite': xml_as_dict['satellite']['name'] + xml_as_dict['satellite']['number'],
        'instrument': xml_as_dict['satellite']['instrument']['#text'],
        # geometric processing: L2, L4, etc.
        'geo_processing': xml_as_dict['image']['level'],
        # radiometric processing: DN or SR
        'radio_processing': radio_processing,
    }

    # create collection name based on its properties (e.g. `CBERS4A_MUX_L2_DN`)
    collection['name'] = (
        f"{collection['satellite']}_{collection['instrument']}_"
        f"L{collection['geo_processing']}_{collection['radio_processing']}"
    )

    # create collection description based on its properties (e.g. `CBERS4A MUX Level2 DN dataset`)
    collection['description'] = (
        f"{collection['satellite']} {collection['instrument']} "
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
        'cloud_cover': ''
    }

    # create item name based on its properties (e.g. `CBERS4A_MUX_070122_20200813`)
    properties['name'] = (
        f"{collection['satellite']}_{collection['instrument']}_"
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
        ]]
    }


def get_dn_item_from_xml_as_dict(xml_as_dict, radio_processing='DN'):
    '''Get Item from an XML file as dictionary.'''

    item = {}

    item['collection'] = get_collection_from_xml_as_dict(xml_as_dict, radio_processing)
    item['properties'] = get_properties_from_xml_as_dict(xml_as_dict, item['collection'])
    item['bbox'] = get_bbox_from_xml_as_dict(xml_as_dict)
    item['geometry'] = get_geometry_from_xml_as_dict(xml_as_dict)

    return item


def get_item_from_xml_as_dict(xml_as_dict):
    '''Get Item from an XML file as dictionary.'''

    # if there is `DN` information in the XML file
    if 'prdf' in xml_as_dict:
        return get_dn_item_from_xml_as_dict(xml_as_dict['prdf'], radio_processing='DN')

    return None
