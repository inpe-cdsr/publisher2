from json import dumps as json_dumps
from os import walk, sep
from os.path import join as os_path_join

from publisher.logger import get_logger
from publisher.util import get_dict_from_xml_file, get_item_from_asset


logger = get_logger(__name__)


class Publisher:
    def __init__(self, BASE_DIR):
        self.BASE_DIR = BASE_DIR

    def main(self):
        for dirpath, dirs, files in walk(self.BASE_DIR):
            # get just bands XMLs from files list
            xml_assets = sorted(filter(lambda f: 'xml' in f and not 'png' in f, files))

            if xml_assets:
                logger.info(f'xml_assets: {xml_assets}')

                # get the first XML asset just to get information, then get the XML asset path
                xml_asset = xml_assets[0]
                xml_asset_path = os_path_join(dirpath, xml_asset)

                logger.info(f'xml_asset: {xml_asset}')
                logger.info(f'xml_asset_path: {xml_asset_path}\n')

                dict_asset = get_dict_from_xml_file(xml_asset_path)

                # logger.info(f'\n dict_asset: {json_dumps(dict_asset)}')

                item = get_item_from_asset(dict_asset)

                logger.info(f'item: {item}\n\n')
