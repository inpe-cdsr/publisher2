from datetime import datetime
from itertools import islice

from celery import Celery
from celery.utils.log import get_task_logger
from pandas import DataFrame

from publisher.model import DBFactory, PostgreSQLPublisherConnection
from publisher.workers.environment import CELERY_BROKER_URL, CELERY_CHUNKS_PER_TASKS
from publisher.util import create_item_and_get_insert_clauses, \
                           PublisherWalk, SatelliteMetadata


logger = get_task_logger(__name__)


CELERY_MASTER_QUEUE='master'
CELERY_PROCESSING_QUEUE='processing'

# initialize Celery
celery = Celery(
    'publisher.workers.processing',  # celery name
    broker=CELERY_BROKER_URL,
    # backend=CELERY_RESULT_BACKEND
)

# get configuration from file
celery.config_from_object('publisher.workers.celery_config')


@celery.task(queue=CELERY_MASTER_QUEUE, name='publisher.workers.processing.master')
def master(base_dir: str, query: dict, df_collections: dict) -> None:
    '''Master task. It calls the workers.'''

    logger.info(f'master - base_dir: {base_dir}')
    logger.info(f'master - query: {query}\n')

    # convert dates from str to date
    query['start_date'] = datetime.strptime(query['start_date'].split('T')[0], '%Y-%m-%d')
    query['end_date'] = datetime.strptime(query['end_date'].split('T')[0], '%Y-%m-%d')

    # p_walk is a generator that returns just valid directories
    p_walk = PublisherWalk(base_dir, query, SatelliteMetadata())

    # run the tasks by chunks.
    while True:
        # exhaust the generator to get a list of values, because generator is not serializable
        p_walk_top = list(islice(p_walk, CELERY_CHUNKS_PER_TASKS)) # get the first N elements

        # if the p_walk generator has been exhausted, then stop the generate_chunk_params generator
        if not p_walk_top:
            break

        logger.info(f'master - p_walk_top: {p_walk_top}')

        # run `process_items` task
        process_items.apply_async(
            (p_walk_top, df_collections), queue=CELERY_PROCESSING_QUEUE
        )

    # save the errors
    p_walk.save_the_errors_in_the_database()

    logger.info('`master` task has been executed...\n')


@celery.task(queue=CELERY_PROCESSING_QUEUE, name='publisher.workers.processing.process_items')
def process_items(p_walk: list, df_collections: dict) -> None:
    '''Worker task that iterate over p_walk list and processes the items.'''

    logger.info(f'process_items - p_walk: {p_walk}\n')

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

    logger.info(f'process_items - items_insert: {items_insert}\n')
    logger.info(f'process_items - errors_insert: {errors_insert}\n')

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
