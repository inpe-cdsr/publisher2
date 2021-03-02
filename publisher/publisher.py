from werkzeug.exceptions import BadRequest

from publisher.common import print_line
from publisher.environment import PR_LOGGING_LEVEL, PR_TASK_CHUNKS
from publisher.logger import create_logger
from publisher.validator import validate, QUERY_SCHEMA
from publisher.workers import CELERY_TASK_QUEUE, master


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

        # run `master` task
        task = master.apply_async(
            (self.BASE_DIR, self.query, self.df_collections.to_dict()),
            queue='master'
        )

        # do not wait all chunks execute, because it will block the request
        logger.info('`master` task has been executed...')

        print_line()
