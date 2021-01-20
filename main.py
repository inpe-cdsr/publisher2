#!/usr/bin/env python3
# -*- coding:utf-8 -*-

from publisher import Publisher
from publisher.environment import BASE_DIR


if __name__ == "__main__":
    app = Publisher(BASE_DIR)
    app.main()
