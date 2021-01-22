from json import loads
from os import walk
from os.path import join as os_path_join, dirname, abspath

from publisher.logger import get_logger
from publisher.util import create_item_from_xml_as_dict, get_dict_from_xml_file


# create logger object
logger = get_logger(__name__)


class Publisher:
    def __init__(self, BASE_DIR):
        # base directory to search the files
        self.BASE_DIR = BASE_DIR
        self.items = []
        self.SATELLITES = None
        self._read_metadata_file()

    def _read_metadata_file(self):
        '''Read JSON satellite metadata file.'''

        # dirname(abspath(__file__)): project's root directory
        satellites_path = os_path_join(dirname(abspath(__file__)), 'metadata', 'satellites.json')

        with open(satellites_path, 'r') as data:
            # read JSON file and convert it to dict
            self.SATELLITES = loads(data.read())

    def main(self):
        '''Main method.'''

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

                item = create_item_from_xml_as_dict(dict_asset)

                logger.info(f'item: {item}\n\n')

                self.items.append(item)

        logger.info(f'self.items: {self.items}\n\n')
        logger.info(f'self.SATELLITES: {self.SATELLITES}\n\n')
