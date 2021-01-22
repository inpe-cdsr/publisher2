from xmltodict import parse as xmltodict_parse

from publisher.common import fill_string_with_left_zeros


def get_dict_from_xml_file(xml_path):
    # read the XML file, convert it to dict and return
    with open(xml_path, 'r') as data:
        return xmltodict_parse(data.read())


def get_collection_from_xml_as_dict(xml_as_dict, radio_processing):
    '''Get collection information from XML file as dict'''

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
    '''Get properties information from XML file as dict'''

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


def get_dn_item_from_asset(asset, radio_processing='DN'):
    '''Get Item from an XML file as dict'''

    item = {}

    item['collection'] = get_collection_from_xml_as_dict(asset, radio_processing)
    item['properties'] = get_properties_from_xml_as_dict(asset, item['collection'])

    # label: UL - upper left; UR - upper right; LR - bottom right; LL - bottom left

    # create bbox object
    # specification: https://tools.ietf.org/html/rfc7946#section-5
    # `all axes of the most southwesterly point followed by all axes of the more northeasterly point`
    item['bbox'] = [
        asset['image']['imageData']['LL']['longitude'], # bottom left longitude
        asset['image']['imageData']['LL']['latitude'], # bottom left latitude
        asset['image']['imageData']['UR']['longitude'], # upper right longitude
        asset['image']['imageData']['UR']['latitude'], # upper right latitude
    ]

    # create geometry object
    # specification: https://tools.ietf.org/html/rfc7946#section-3.1.6
    item['geometry'] = {
        'type': 'Polygon',
        'coordinates': [[
            [asset['image']['imageData']['UL']['longitude'], asset['image']['imageData']['UL']['latitude']],
            [asset['image']['imageData']['UR']['longitude'], asset['image']['imageData']['UR']['latitude']],
            [asset['image']['imageData']['LR']['longitude'], asset['image']['imageData']['LR']['latitude']],
            [asset['image']['imageData']['LL']['longitude'], asset['image']['imageData']['LL']['latitude']],
            [asset['image']['imageData']['UL']['longitude'], asset['image']['imageData']['UL']['latitude']]
        ]]
    }

    return item


def get_item_from_asset(asset):
    '''Get Item from asset'''

    # if there is `DN` information in the asset
    if 'prdf' in asset:
        return get_dn_item_from_asset(asset['prdf'], radio_processing='DN')

    return None
