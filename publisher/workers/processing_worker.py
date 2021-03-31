from celery import Celery
from celery.utils.log import get_task_logger
from pandas import DataFrame

from publisher.common import print_line
from publisher.model import DBFactory, PostgreSQLPublisherConnection
from publisher.workers.decorator import log_task
from publisher.workers.environment import CELERY_BROKER_URL, CELERY_RESULT_BACKEND
from publisher.util import create_item_and_get_insert_clauses


logger = get_task_logger(__name__)


CELERY_PROCESSING_QUEUE='processing'

# initialize Celery
celery = Celery(
    'publisher.workers.processing_worker',  # celery name
    broker=CELERY_BROKER_URL,
    backend=CELERY_RESULT_BACKEND
)

# get configuration from file
celery.config_from_object('publisher.workers.celery_config')


@celery.task(bind=True, queue=CELERY_PROCESSING_QUEUE,
             name='publisher.workers.processing_worker.process_items')
@log_task
def process_items(self, p_walk: list, df_collections: dict) -> None:
    '''Worker task that iterate over p_walk list and processes the items.'''

    print_line()

    logger.info(f'process_items - `{len(p_walk)}` chunks have been received.')
    logger.info(f'process_items - p_walk first record: {p_walk[0]}')
    logger.info(f'process_items - p_walk last record: {p_walk[-1]}')

    # convert from dict to dataframe again
    df_collections = DataFrame.from_dict(df_collections)

    items_insert = []
    errors_insert = []

    for dir_path, metadata, assets in p_walk:
        # create INSERT clause based on item information
        __items_insert, __errors_insert = create_item_and_get_insert_clauses(
            dir_path, metadata, assets, df_collections
        )

        items_insert += __items_insert
        errors_insert += __errors_insert

    # if there are INSERT clauses, then insert them in the database
    if items_insert:
        # logger.info(f'process_items - items_insert: {items_insert}\n')
        logger.info(f'process_items - there are `{len(items_insert)}` '
                     'items to insert in the database.')
        # if there is INSERT clauses to insert in the database,
        # then create a database instance and insert them there
        db = DBFactory.factory()
        concanate_inserts = ' '.join(items_insert)
        # logger.info(f'concanate_inserts: \n{concanate_inserts}\n')
        logger.info('process_items - inserting items in the database...')
        db.execute(concanate_inserts, is_transaction=True)

    # if there are INSERT clauses, then insert them in the database
    if errors_insert:
        # logger.info(f'process_items - errors_insert: {errors_insert}\n')
        logger.info(f'process_items - there are `{len(errors_insert)}` '
                     'warnings or errors to insert in the database.')
        # if there is INSERT clauses to insert in the database,
        # then create a database instance and insert them there
        db = PostgreSQLPublisherConnection()
        concanate_errors = ' '.join(errors_insert)
        # logger.info(f'concanate_errors: \n{concanate_errors}\n')
        logger.info('process_items - inserting task errors in the database...')
        db.execute(concanate_errors, is_transaction=True)
