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

    # statistics
    tasks_count = 0  # number of executed tasks
    chunks_per_tasks_count = 0  # number of chunks per tasks

    # run the tasks by chunks.
    while True:
        # exhaust the generator to get a list of values, because generator is not serializable
        p_walk_top = list(islice(p_walk, CELERY_CHUNKS_PER_TASKS)) # get the first N elements

        # logger.info(f'master - p_walk_top: {p_walk_top}')

        # if the p_walk generator has been exhausted, then stop the generate_chunk_params generator
        if not p_walk_top:
            break

        # get the number of records to process
        p_walk_top_size = len(p_walk_top)

        logger.info(f'master - sending `{p_walk_top_size}` chunks to `process_items` task.')

        # run `process_items` task
        process_items.apply_async((p_walk_top, df_collections), queue=CELERY_PROCESSING_QUEUE)

        # get statistics
        chunks_per_tasks_count += p_walk_top_size
        tasks_count += 1

        logger.info(f'master - `{chunks_per_tasks_count}` chunks per tasks have been sent to '
                    '`process_items` task.')
        logger.info(f'master - `{tasks_count}` `process_items` tasks have been executed.')

    # save the errors
    p_walk.save_the_errors_in_the_database()

    logger.info('`master` task has been executed...\n')
