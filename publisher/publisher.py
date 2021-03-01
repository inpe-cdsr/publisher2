from itertools import islice
from json import loads
from os.path import join as os_path_join, dirname, abspath

from pandas import read_csv
from werkzeug.exceptions import BadRequest

from publisher.common import print_line
from publisher.environment import PR_FILES_PATH, PR_LOGGING_LEVEL, PR_TASK_CHUNKS
from publisher.logger import create_logger
from publisher.model import PostgreSQLPublisherConnection
from publisher.util import PublisherWalk
from publisher.validator import validate, QUERY_SCHEMA
from publisher.workers import CELERY_TASK_QUEUE, process_items


# create logger object
logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


def generate_chunk_params(p_walk, df_collections, islice_stop=10):
    dict_collections = df_collections.to_dict()

    while True:
        # exhaust the generator to get a list of values, because generator is not serializable
        p_walk_top = list(islice(p_walk, islice_stop)) # get the first N elements

        # if the p_walk generator has been exhausted, then stop the generate_chunk_params generator
        if not p_walk_top:
            break

        yield p_walk_top, dict_collections


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

    def __init__(self, BASE_DIR, db_connection, query=None):
        # base directory to search the files
        self.BASE_DIR = BASE_DIR
        self.db = db_connection
        self.query = query

        # get all available collections from database and save the result in a CSV file
        self.df_collections = self.db.select_from_collections()

    def main(self):
        '''Main method.'''

        logger.info('Publisher.main()')

        print_line()

        logger.info(f'BASE_DIR: {self.BASE_DIR}')
        logger.info(f'PR_TASK_CHUNKS: {PR_TASK_CHUNKS}')
        logger.info(f'CELERY_TASK_QUEUE: {CELERY_TASK_QUEUE}')
        logger.info(f'df_collections:\n{self.df_collections}')

        # validate self.query
        is_valid, self.query, errors = validate(self.query, QUERY_SCHEMA)
        if not is_valid:
            raise BadRequest(errors)

        logger.info(f'query: {self.query}')
        print_line()

        # p_walk is a generator that returns just valid directories
        p_walk = PublisherWalk(self.BASE_DIR, self.query, SatelliteMetadata())

        # run the tasks by chunks. PR_TASK_CHUNKS chunks are sent to one task
        tasks = process_items.chunks(
            generate_chunk_params(p_walk, self.df_collections), PR_TASK_CHUNKS
        ).apply_async(queue=CELERY_TASK_QUEUE)

        # do not wait all chunks execute, because it will block the request
        logger.info('Tasks have been executed...')

        p_walk.save_the_errors_in_the_database()
        print_line()
