from werkzeug.exceptions import BadRequest

from publisher.common import print_line
from publisher.environment import PR_FILES_PATH, PR_LOGGING_LEVEL, PR_TASK_CHUNKS
from publisher.logger import create_logger
from publisher.model import PostgreSQLPublisherConnection
from publisher.util import generate_chunk_params, PublisherWalk, SatelliteMetadata
from publisher.validator import validate, QUERY_SCHEMA
from publisher.workers import CELERY_TASK_QUEUE, process_items


# create logger object
logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


class Publisher:

    def __init__(self, BASE_DIR, df_collections, query=None):
        # base directory to search the files
        self.BASE_DIR = BASE_DIR
        self.df_collections = df_collections
        self.query = query

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
