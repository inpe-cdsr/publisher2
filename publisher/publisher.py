from json import loads
from os.path import join as os_path_join, dirname, abspath

from pandas import read_csv
from werkzeug.exceptions import BadRequest

from publisher.common import print_line
from publisher.environment import PR_FILES_PATH, PR_LOGGING_LEVEL
from publisher.logger import create_logger
from publisher.util import create_item_and_get_insert_clauses, PublisherWalk
from publisher.validator import validate, QUERY_SCHEMA
from publisher.workers import add_nums


# create logger object
logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


class SatelliteMetadata:

    def __init__(self):
        self.SATELLITES = None

        # read satellites metadata file
        self.__read_metadata_file()

    def __read_metadata_file(self):
        '''Read JSON satellite metadata file.'''

        # dirname(abspath(__file__)): project's root directory
        satellites_path = os_path_join(dirname(abspath(__file__)), 'metadata', 'satellites.json')

        with open(satellites_path, 'r') as data:
            # read JSON file and convert it to dict
            self.SATELLITES = loads(data.read())

    def get_assets_metadata(self, satellite=None, sensor=None, radio_processing=None, **kwargs):
        '''Get assets metadata based on the parameters.'''

        # get the satellite information
        satellite = list(filter(lambda s: s['name'] == satellite, self.SATELLITES['satellites']))

        # if a satellite has not been found, then return None
        if not satellite:
            return None

        # if a satellite has been found, then get the unique value inside the list
        # and get the sensor information
        sensor = list(filter(lambda s: s['name'] == sensor, satellite[0]['sensors']))

        # if a sensor has not been found, then return None
        if not sensor:
            return None

        # if a sensor has been found, then get the unique value inside the list
        # and return assets metadata based on the radiometric processing (i.e. DN or SR)
        return  sensor[0]['assets'][radio_processing]


class Publisher:

    def __init__(self, BASE_DIR, IS_TO_GET_DATA_FROM_DB, db_connection, query=None):
        # base directory to search the files
        self.BASE_DIR = BASE_DIR
        self.IS_TO_GET_DATA_FROM_DB = IS_TO_GET_DATA_FROM_DB
        self.db = db_connection
        self.errors = []
        self.query = query

        if self.IS_TO_GET_DATA_FROM_DB:
            # get all available collections from database and save the result in a CSV file
            self.df_collections = self.db.select_from_collections()
            self.df_collections.to_csv(f'{PR_FILES_PATH}/collections.csv', index=False)
        else:
            # get all available collections from CSV file
            self.df_collections = read_csv(f'{PR_FILES_PATH}/collections.csv')

    def main(self):
        '''Main method.'''

        logger.info('Publisher.main()')

        print_line()
        logger.info(f'BASE_DIR: {self.BASE_DIR}')
        logger.info(f'IS_TO_GET_DATA_FROM_DB: {self.IS_TO_GET_DATA_FROM_DB}')
        logger.debug(f'df_collections:\n{self.df_collections}')

        # validate self.query
        is_valid, self.query, errors = validate(self.query, QUERY_SCHEMA)
        if not is_valid:
            raise BadRequest(errors)

        logger.info(f'query: {self.query}')
        print_line()

        # list to save the INSERT clauses based on item metadata
        items_insert = []
        # p_walk is a generator that returns just valid directories
        p_walk = PublisherWalk(self.BASE_DIR, self.query, SatelliteMetadata())

        for dir_path, dn_xml_file_path, assets in p_walk:
            # create INSERT clause based on item information
            result = create_item_and_get_insert_clauses(
                dir_path, dn_xml_file_path, assets, self.df_collections
            )

            logger.info(f'result: {result}')

            # if INSERT clauses have been returned, then add them to the list
            if result['items_insert']:
                items_insert += result['items_insert']

            if result['errors']:
                self.errors += result['errors']

        print_line()

        # if there are INSERT clauses, then insert them in the database
        if items_insert:
            concanate_inserts = ' '.join(items_insert)
            # logger.info(f'concanate_inserts: \n{concanate_inserts}\n')
            logger.info('Inserting items into database...')
            self.db.execute(concanate_inserts, is_transaction=True)

        # add the walk errors in the publisher errors list
        self.errors += p_walk.errors
