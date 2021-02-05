from json import loads
from os.path import join as os_path_join, dirname, abspath

from pandas import read_csv
from werkzeug.exceptions import BadRequest

from publisher.common import print_line
from publisher.environment import PR_FILES_PATH, PR_LOGGING_LEVEL
from publisher.logger import create_logger
from publisher.util import create_assets_from_metadata, create_insert_clause, \
                           create_items_from_xml_as_dict, PublisherWalk
from publisher.validator import validate, QUERY_SCHEMA


# create logger object
logger = create_logger(__name__, level=PR_LOGGING_LEVEL)


class Publisher:
    def __init__(self, BASE_DIR, IS_TO_GET_DATA_FROM_DB, db_connection, query=None):
        # base directory to search the files
        self.BASE_DIR = BASE_DIR
        self.IS_TO_GET_DATA_FROM_DB = IS_TO_GET_DATA_FROM_DB
        self.SATELLITES = None
        self.db = db_connection
        self.errors = []
        self.query = query

        # read satellites metadata file
        self.__read_metadata_file()

        if self.IS_TO_GET_DATA_FROM_DB:
            # get all available collections from database and save the result in a CSV file
            self.df_collections = self.db.select_from_collections()
            self.df_collections.to_csv(f'{PR_FILES_PATH}/collections.csv', index=False)
        else:
            # get all available collections from CSV file
            self.df_collections = read_csv(f'{PR_FILES_PATH}/collections.csv')

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
        # and get the sensor information
        sensor = list(filter(lambda s: s['name'] == sensor, satellite[0]['sensors']))

        # if a sensor has not been found, then return None
        if not sensor:
            return None

        # if a sensor has been found, then get the unique value inside the list
        # and return assets metadata based on the radiometric processing (i.e. DN or SR)
        return  sensor[0]['assets'][radio_processing]

    def main(self):
        '''Main method.'''

        logger.info('Publisher.main()')

        print_line()
        logger.info(f'BASE_DIR: {self.BASE_DIR}')
        logger.info(f'IS_TO_GET_DATA_FROM_DB: {self.IS_TO_GET_DATA_FROM_DB}')
        logger.debug(f'df_collections:\n{self.df_collections}')

        is_valid, self.query, errors = validate(self.query, QUERY_SCHEMA)

        # validate self.query
        if not is_valid:
            raise BadRequest(errors)

        logger.info(f'query: {self.query}')
        print_line()

        # list to save the INSERT clauses based on item metadata
        items_insert = []

        p_walk = PublisherWalk(self.BASE_DIR, self.query)

        for dir_path, xml_as_dict, radio_processing_list in p_walk:
            print_line()
            logger.info(f'dir_path: {dir_path}')
            # logger.info(f'xml_as_dict: {xml_as_dict}')
            logger.info(f'radio_processing_list: {radio_processing_list}')

            items = create_items_from_xml_as_dict(xml_as_dict, radio_processing_list)
            logger.info(f'items size: {len(items)}\n')

            for item in items:
                print_line()
                logger.info(f'item: {item}\n')

                assets_matadata = self.__get_assets_metadata(**item['collection'])
                logger.info(f'assets_matadata: {assets_matadata}\n')

                item['assets'] = create_assets_from_metadata(assets_matadata, dir_path)
                logger.info(f'item[assets]: {item["assets"]}\n')

                logger.info(f'item[collection][name]: {item["collection"]["name"]}')

                # get collection id from dataframe
                collection = self.df_collections.loc[
                    self.df_collections['name'] == item['collection']['name']
                ].reset_index(drop=True)
                logger.info(f'collection:\n{collection}')

                # if `collection` is an empty dataframe, a collection was not found by its name,
                # then save the warning and ignore it
                if len(collection.index) == 0:
                    # check if the collection has not already been added to the errors list
                    if not any(e['metadata']['collection'] == item['collection']['name'] \
                              for e in self.errors):
                        self.errors.append({
                            'type': 'warning',
                            'message': (
                                f'There is metadata to the `{item["collection"]["name"]}` collection, '
                                f'however this collection does not exist in the database.'
                            ),
                            'metadata': {
                                'collection': item['collection']['name']
                            }
                        })
                    continue

                collection_id = collection.at[0, 'id']
                logger.info(f'collection_id: {collection_id}')

                # create INSERT clause based on item information
                insert = create_insert_clause(item, collection_id)
                logger.info(f'insert: {insert}')
                items_insert.append(insert)

        print_line()

        # if there are INSERT clauses, then insert them in the database
        if items_insert:
            concanate_inserts = ' '.join(items_insert)
            # logger.info(f'concanate_inserts: \n{concanate_inserts}\n')
            logger.info('Inserting items into database...')
            self.db.execute(concanate_inserts, is_transaction=True)

        # add the walk errors in the publisher errors list
        self.errors += p_walk.errors
