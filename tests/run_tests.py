#!/usr/bin/env python
# -*- coding: utf-8 -*-

from sys import exit as sys_exit, path as sys_path
from os import path as os_path

from coverage import Coverage

from unittest import TestLoader, TestSuite, TextTestRunner


# get the root path
ROOT_PATH = os_path.sep.join(os_path.abspath(__file__).split(os_path.sep)[:-2])
# add the root path in the sys path to use the folders (modules, settings, etc) as modules
sys_path.append(os_path.abspath(ROOT_PATH))

# get the current folder path, where the run_tests.py is, to use the TestLoader
TEST_PATH = os_path.dirname(__file__)


def init_dbs():
    from publisher.model import PostgreSQLCatalogTestConnection, PostgreSQLPublisherConnection

    # initialize the databases just one time
    db = PostgreSQLCatalogTestConnection()
    db.init_db()
    db_publisher = PostgreSQLPublisherConnection()
    db_publisher.init_db()

    print('Databases have been initialized\n')


if __name__ == '__main__':
    print('Running the test cases\n')

    cov = Coverage()
    cov.start()

    # initialize the databases before running the test cases
    init_dbs()

    # get all the test files on the current folder
    tests = TestLoader().discover(TEST_PATH, 'test_*.py')

    # run the tests
    result = TextTestRunner(verbosity=2).run(tests)

    cov.stop()
    cov.save()

    cov.report(show_missing=True)
    cov.html_report()

    # if a problem has happened, close the program
    if not result.wasSuccessful():
        sys_exit(1)
