from json import loads
from os.path import join as os_path_join, dirname, abspath

from pandas import read_csv
from werkzeug.exceptions import BadRequest

from publisher.common import print_line
from publisher.environment import PR_FILES_PATH, PR_LOGGING_LEVEL
from publisher.logger import create_logger
from publisher.util import create_assets_from_metadata, create_insert_clause, \
                           create_items_from_xml_as_dict, get_dn_files_as_dicts_from_files, \
                           get_sr_files_as_dicts_from_files, PublisherWalk
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

    def __get_dn_xml_file(self, files, dir_path):
        '''Return just one DN XML file inside the directory as a dictionary.'''

        radio_processing = self.query['radio_processing']

        # if radio_processing is not DN, SR or None, then it is invalid
        if radio_processing == 'DN':
            # user chose to publish just `DN` files
            return get_dn_files_as_dicts_from_files(files, dir_path), ['DN']

        elif radio_processing == 'SR':
            # user chose to publish just `SR` files
            sr_xml_files = get_sr_files_as_dicts_from_files(files)

            # if there are SR files, then I will extract the information from the DN file
            if sr_xml_files:
                return get_dn_files_as_dicts_from_files(files, dir_path), ['SR']

        elif radio_processing is None:
            # user chose to publish bothm `DN` and `SR` files
            sr_xml_files = get_sr_files_as_dicts_from_files(files)
            dn_xml_files = get_dn_files_as_dicts_from_files(files, dir_path)

            # if there are both DN and SR files, then I will publish
            # information from both radiometric processings
            if dn_xml_files and sr_xml_files:
                return dn_xml_files, ['DN', 'SR']

            # if there are just DN files, then I will publish information
            # from the DN radiometric processing
            elif dn_xml_files and not sr_xml_files:
                return dn_xml_files, ['DN']

            else: # elif (not dn_xml_files and sr_xml_files) or (not dn_xml_files and not sr_xml_files):
                # if there is NOT DN XML files in the folder, then I save the error
                self.errors.append(
                    {
                        'type': 'warning',
                        'message': 'There is NOT a DN XML file in this folder.',
                        'metadata': {
                            'folder': dir_path
                        }
                    }
                )

                return None, []

        raise InternalServerError(f'Invalid radiometric processing: {radio_processing}')

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
        # p_walk is a generator that returns just valid directories
        p_walk = PublisherWalk(self.BASE_DIR, self.query)

        for dir_path, files in p_walk:
            print_line()
            logger.info(f'dir_path: {dir_path}')

            # if a valid dir does not have files, then ignore it
            xml_as_dict, radio_processing_list = self.__get_dn_xml_file(files, dir_path)
            if not xml_as_dict:
                continue

            # logger.info(f'xml_as_dict: {xml_as_dict}')
            logger.info(f'radio_processing_list: {radio_processing_list}')

            # list of items (e.g. [dn_item, sr_item])
            items = create_items_from_xml_as_dict(xml_as_dict, radio_processing_list)
            logger.info(f'items size: {len(items)}\n')

            for item in items:
                print_line()
                logger.info(f'item: {item}\n')

                assets_metadata = self.__get_assets_metadata(**item['collection'])
                logger.info(f'assets_metadata: {assets_metadata}\n')

                item['assets'] = create_assets_from_metadata(assets_metadata, dir_path)
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
                                'however this collection does not exist in the database.'
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
