from json import dumps as json_dumps
from os import walk, sep
from os.path import join as os_path_join

from publisher.util import get_dict_from_xml_file


class Publisher:
    def __init__(self, BASE_DIR):
        self.BASE_DIR = BASE_DIR

    def main(self):
        for dirpath, dirs, files in walk(self.BASE_DIR):
            # get just bands XMLs from files list
            xml_assets = sorted(filter(lambda f: 'xml' in f and not 'png' in f, files))

            if xml_assets:
                print('\n\nxml_assets: ', xml_assets)
                # print('\n files: ', files, '\n')

                # get the first XML asset just to get information, then get the XML asset path
                xml_asset = xml_assets[0]
                xml_asset_path = os_path_join(dirpath, xml_asset)

                print('xml_asset: ', xml_asset)
                print('xml_asset_path: ', xml_asset_path)

                dict_asset = get_dict_from_xml_file(xml_asset_path)

                print('\n dict_asset: ', json_dumps(dict_asset))
