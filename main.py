#!/usr/bin/env python3
# -*- coding:utf-8 -*-

from publisher import Publisher
from publisher.environment import BASE_DIR, IS_TO_GET_DATA_FROM_DB


if __name__ == '__main__':
    query = {
        'start_date': '2019-12-27',
        'end_date': '2019-12-28',
        'path': 215,
        'row': 132,
        'satellite': 'CBERS4A',
        'sensor': 'WFI',
        'geo_processing': 4,
        'radio_processing': 'DN'
    }

    app = Publisher(BASE_DIR, IS_TO_GET_DATA_FROM_DB, query=query)
    app.main()
