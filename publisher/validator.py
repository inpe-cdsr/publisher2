from cerberus import Validator
from datetime import datetime


# function to convert from string to datetime
to_date = lambda s: datetime.strptime(s, '%Y-%m-%d')

# function to transform the string on upper case
to_upper_case = lambda s: s.upper()


class PublisherValidator(Validator):
    def _validate_it_cannot_be_greater_than(self, target_field, self_field, self_value):
        '''Check if the field is greater than the other one.
        First field cannot be greater than the other one.

        The rule's arguments are validated against this schema:
        {'type': 'string'}
        '''

        if target_field not in self.document:
            self._error(self_field, f'Field {target_field} is not in the document.')

        target_value = self.document[target_field]
        if self_value > target_value:
            self._error(self_field, f'`{self_field}` field is greater than `{target_field}` field.')


QUERY_SCHEMA = {
    'satellite': {
        'type': 'string', 'coerce': to_upper_case, 'regex': 'AMAZONIA1|^CBERS[1-4][A-B]*|^LANDSAT\d',
        'required': True
    },
    'sensor': {
        'type': 'string', 'coerce': to_upper_case,
        'default': None, 'nullable': True
    },
    'start_date': {
        'type': 'datetime', 'coerce': to_date, 'it_cannot_be_greater_than': 'end_date',
        'required': True
    },
    'end_date': {
        'type': 'datetime', 'coerce': to_date,
        'required': True
    },
    'path': {
        'type': 'integer', 'coerce': int, 'min': 1, 'max': 999,
        'default': None, 'nullable': True
    },
    'row': {
        'type': 'integer', 'coerce': int, 'min': 1, 'max': 999,
        'default': None, 'nullable': True
    },
    'geo_processing': {
        'type': 'integer', 'coerce': int, 'min': 1, 'max': 4,
        'default': None, 'nullable': True
    },
    'radio_processing': {
        'type': 'string', 'coerce': to_upper_case, 'allowed': ['DN', 'SR'],
        'default': None, 'nullable': True
    }
}


def validate(data, schema):
    v = PublisherValidator(schema)
    is_valid = v.validate(data)

    if is_valid:
        radio_processing = v.document['radio_processing']

        if radio_processing == 'DN':
            v.document['radio_processing'] = ['DN']
        elif radio_processing == 'SR':
            v.document['radio_processing'] = ['SR']
        else: # elif radio_processing is None
            v.document['radio_processing'] = ['DN', 'SR']

    return is_valid, v.document, v.errors
