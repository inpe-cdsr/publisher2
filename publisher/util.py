from xmltodict import parse as xmltodict_parse

from publisher.common import fill_string_with_left_zeros


def get_dict_from_xml_file(xml_path):
    # read the XML file, convert it to dict and return
    with open(xml_path, 'r') as data:
        return xmltodict_parse(data.read())


def get_dn_item_from_asset(asset):
    '''Get DN Item from asset'''

    item = {}

    item['collection'] = {
        'satellite': asset['satellite']['name'] + asset['satellite']['number'],
        'instrument': asset['satellite']['instrument']['#text'],
        # geometric processing: L2, L4, etc.
        'geo_processing': asset['image']['level'],
        # radiometric processing: DN or SR
        'radio_processing': 'DN',
    }

    # create collection name based on its properties (e.g. `CBERS4A_MUX_L2_DN`)
    item['collection']['name'] = (
        f"{item['collection']['satellite']}_{item['collection']['instrument']}_"
        f"L{item['collection']['geo_processing']}_{item['collection']['radio_processing']}"
    )

    # create collection description based on its properties (e.g. `CBERS4A MUX Level2 DN dataset`)
    item['collection']['description'] = (
        f"{item['collection']['satellite']} {item['collection']['instrument']} "
        f"Level {item['collection']['geo_processing']} {item['collection']['radio_processing']} "
        'dataset'
    )

    # get the item's properties
    item['properties'] = {
        # get just the date and time of the string
        'datetime': asset['viewing']['center'][0:19],
        'path': fill_string_with_left_zeros(asset['image']['path']),
        'row': fill_string_with_left_zeros(asset['image']['row']),
        # CQ fills it
        'cloud_cover': ''
    }

    # create item name based on its properties (e.g. `CBERS4A_MUX_070122_20200813`)
    item['properties']['name'] = (
        f"{item['collection']['satellite']}_{item['collection']['instrument']}_"
        f"{item['properties']['path']}{item['properties']['row']}_"
        f"{item['properties']['datetime'].split('T')[0].replace('-', '')}"
    )

    # label: UL - upper left; UR - upper right; LR - bottom right; LL - bottom left

    # create bbox object
    # specification: https://tools.ietf.org/html/rfc7946#section-5
    # `all axes of the most southwesterly point followed by all axes of the more northeasterly point`
    item['properties']['bbox'] = [
        asset['image']['imageData']['LL']['longitude'], # bottom left longitude
        asset['image']['imageData']['LL']['latitude'], # bottom left latitude
        asset['image']['imageData']['UR']['longitude'], # upper right longitude
        asset['image']['imageData']['UR']['latitude'], # upper right latitude
    ]

    # create geometry object
    # specification: https://tools.ietf.org/html/rfc7946#section-3.1.6
    item['properties']['geometry'] = {
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
        return get_dn_item_from_asset(asset['prdf'])

    return None
