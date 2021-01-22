from xmltodict import parse as xmltodict_parse


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
        'datetime': asset['viewing']['center'][0:18],
        'path': asset['image']['path'],
        'row': asset['image']['row'],
        'cloud_cover': ''
    }

    # create name (old scene_id) based on its properties (e.g. CBERS4A_MUX_070122_20200813)
    item['properties']['name'] = (
        f"{item['collection']['satellite']}_{item['collection']['instrument']}_"
        f"{item['properties']['path']}{item['properties']['row']}_"
        f"{item['properties']['datetime']}"
    )

    return item


def get_item_from_asset(asset):
    '''Get Item from asset'''

    # if there is `DN` information in the asset
    if 'prdf' in asset:
        return get_dn_item_from_asset(asset['prdf'])

    return None
