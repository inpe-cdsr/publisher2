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
        'geo_processing': 'L' + asset['image']['level'],
        # radiometric processing: DN or SR
        'radio_processing': 'DN',
    }

    item['properties'] = {
        # get just the date and time of the string
        'datetime': asset['viewing']['center'][0:19],
        'path': fill_string_with_left_zeros(asset['image']['path']),
        'row': fill_string_with_left_zeros(asset['image']['row']),
        # CQ fills it
        'cloud_cover': ''
    }

    # create name (old scene_id) based on its properties (e.g. CBERS4A_MUX_070122_20200813)
    item['properties']['name'] = (
        f"{item['collection']['satellite']}_{item['collection']['instrument']}_"
        f"{item['properties']['path']}{item['properties']['row']}_"
        f"{item['properties']['datetime'].split('T')[0].replace('-', '')}"
    )

    return item


def get_item_from_asset(asset):
    '''Get Item from asset'''

    # if there is `DN` information in the asset
    if 'prdf' in asset:
        return get_dn_item_from_asset(asset['prdf'])

    return None
