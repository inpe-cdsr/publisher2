from datetime import datetime
from itertools import islice

from celery import Celery
from celery.utils.log import get_task_logger

from publisher.workers.environment import CELERY_BROKER_URL, CELERY_CHUNKS_PER_TASKS
from publisher.workers.processing_worker import process_items, CELERY_PROCESSING_QUEUE
from publisher.util import PublisherWalk, SatelliteMetadata


logger = get_task_logger(__name__)


CELERY_MASTER_QUEUE='master'

# initialize Celery
celery = Celery(
    'publisher.workers.master_worker',  # celery name
    broker=CELERY_BROKER_URL,
    # backend=CELERY_RESULT_BACKEND
)

# get configuration from file
celery.config_from_object('publisher.workers.celery_config')


@celery.task(queue=CELERY_MASTER_QUEUE, name='publisher.workers.master_worker.master')
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

        logger.info(f'master - sending `{CELERY_CHUNKS_PER_TASKS}` chunks to `process_items` task.')

        # run `process_items` task
        process_items.apply_async(
            (p_walk_top, df_collections), queue=CELERY_PROCESSING_QUEUE
        )

    # save the errors
    p_walk.save_the_errors_in_the_database()

    logger.info('`master` task has been executed...\n')
