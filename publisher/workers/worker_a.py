from celery import Celery
from celery.utils.log import get_task_logger
from pandas import DataFrame

from publisher.model import DBFactory, PostgreSQLPublisherConnection
from publisher.workers.environment import CELERY_BROKER_URL, CELERY_RESULT_BACKEND, \
                                          CELERY_TASK_QUEUE
from publisher.util import create_item_and_get_insert_clauses


logger = get_task_logger(__name__)


# initialize Celery
celery = Celery(
    'publisher.workers.worker_a',  # celery name
    broker=CELERY_BROKER_URL,
    backend=CELERY_RESULT_BACKEND
)

# get configuration from file
celery.config_from_object('publisher.workers.celery_config')


@celery.task(queue=CELERY_TASK_QUEUE, name='publisher.workers.worker_a.process_items')
def process_items(p_walk: list, df_collections: dict):
    # convert from dict to dataframe again
    df_collections = DataFrame.from_dict(df_collections)

    items_insert = []
    errors_insert = []

    for dir_path, dn_xml_file_path, assets in p_walk:
        # create INSERT clause based on item information
        __items_insert, __errors_insert = create_item_and_get_insert_clauses(
            dir_path, dn_xml_file_path, assets, df_collections
        )

        items_insert += __items_insert
        errors_insert += __errors_insert

    logger.info(f'process_items - items_insert: {items_insert}')
    logger.info(f'process_items - errors_insert: {errors_insert}')

    # if there are INSERT clauses, then insert them in the database
    if items_insert:
        # if there is INSERT clauses to insert in the database,
        # then create a database instance and insert them there
        db = DBFactory.factory()
        concanate_inserts = ' '.join(items_insert)
        # logger.info(f'concanate_inserts: \n{concanate_inserts}\n')
        logger.info('process_items - inserting items into database...')
        db.execute(concanate_inserts, is_transaction=True)

    # if there are INSERT clauses, then insert them in the database
    if errors_insert:
        # if there is INSERT clauses to insert in the database,
        # then create a database instance and insert them there
        db = PostgreSQLPublisherConnection()
        concanate_errors = ' '.join(errors_insert)
        # logger.info(f'concanate_errors: \n{concanate_errors}\n')
        logger.info('process_items - inserting task errors into database...')
        db.execute(concanate_errors, is_transaction=True)
