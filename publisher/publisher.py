from json import loads
from os.path import join as os_path_join, dirname, abspath

from publisher.logger import get_logger
from publisher.util import create_item_from_xml_as_dict, get_dict_from_xml_file, PublisherWalk


# create logger object
logger = get_logger(__name__)


class Publisher:
    def __init__(self, BASE_DIR):
        # base directory to search the files
        self.BASE_DIR = BASE_DIR
        self.items = []
        self.SATELLITES = None

        self.__read_metadata_file()

    def __read_metadata_file(self):
        '''Read JSON satellite metadata file.'''

        # dirname(abspath(__file__)): project's root directory
        satellites_path = os_path_join(dirname(abspath(__file__)), 'metadata', 'satellites.json')

        with open(satellites_path, 'r') as data:
            # read JSON file and convert it to dict
            self.SATELLITES = loads(data.read())

    def __get_assets_metadata(self, satellite=None, sensor=None, radio_processing=None, **kwargs):
        '''Get assets metadata based on the parameters.'''

        # get the satellite information
        satellite = list(filter(lambda s: s['name'] == satellite, self.SATELLITES['satellites']))

        # if a satellite has not been found, then return None
        if not satellite:
            return None

        # if a satellite has been found, then get the unique value inside the list
        satellite = satellite[0]

        # get the sensor information
        sensor = list(filter(lambda s: s['name'] == sensor, satellite['sensors']))

        # if a sensor has not been found, then return None
        if not sensor:
            return None

        # if a sensor has been found, then get the unique value inside the list
        sensor = sensor[0]

        # return assets metadata based on the radiometric processing (i.e. DN or SR)
        return sensor['assets'][radio_processing]

    def main(self):
        '''Main method.'''

        logger.info('Publisher.main()')

        p_walk = PublisherWalk(self.BASE_DIR)

        # for dir_path, dirs, files in walk(self.BASE_DIR):
        for dir_path, dirs, valid_files, xml_files in p_walk:
            print(f'\n{ "-" * 130 }\n')

            logger.info(f'dir_path: {dir_path}')

            logger.info(f'valid_files: {valid_files}')
            logger.info(f'xml_files: {xml_files}')

            # get the first XML asset just to get information, then get the XML asset path
            xml_file = xml_files[0]
            xml_file_path = os_path_join(dir_path, xml_file)

            logger.info(f'xml_file: {xml_file}')
            logger.info(f'xml_file_path: {xml_file_path}\n')

            # get XML file as dict and create a item with its information
            xml_as_dict = get_dict_from_xml_file(xml_file_path)
            item = create_item_from_xml_as_dict(xml_as_dict)

            logger.info(f'item: {item}\n')

            assets_matadata = self.__get_assets_metadata(**item['collection'])

            logger.info(f'assets_matadata: {assets_matadata}\n')

            for k, v in assets_matadata.items():
                logger.info(f'{k}: {v}')

            # TODO: compare assets_matadata with xml_files and build assets property

            self.items.append(item)

        print('-' * 130, '\n')

        logger.info(f'self.items: {self.items}\n')
        logger.info(f'p_walk.errors: {p_walk.errors}\n')
