Оригинальная документация здесь https://github.com/aparande/json-mapping-transform

## Примеры расширенных возможностей:

### 1. Работа с массивами
```ruby
require 'json_mapping'

j = {
  "name": "Trader Joe's",
  "location": "Berkeley, California",
  "weeklyVisitors": 5000,
  "storeId": 1234,
  "employees": [
    { "name": "Jim Shoes" },
    { "name": "Kay Oss" }
  ],
  "inventory": [
    { "itemName": "Apples", "price": 0.5, "unit": "lb" },
    { "itemName": "Oranges", "price": 2, "unit": "lb" },
    { "itemName": "Bag of Carrots", "price": 1.5, "unit": "count" }
  ]
}

scheme = [
          {
            name: 'name',
            path: '/name'
          },
          {
            name: 'profits',
            default: 0
          },
          {
            'name': 'attributes_examlpe', # массив из массива
            'path': '/inventory/*',
            'attributes': [ 
              {
                'name': 'item_name',
                'path': '/itemName'
              },
              {
                'name': 'price',
                'path': '/price'
              }
            ]
          },
          {
            'name': 'items_examlpe', # массив из элементов одного уровня
            'path': '/',
            'items': [
              [
                {
                  name: 'value',
                  path: '/name',
                },
                {
                  name: 'parameter_id',
                  path: '/location'
                }
              ]
            ]
          },
          {
            'name': 'hash_examlpe', # hash из элементов одного уровня
            'path': '/',
            'hash': [ 
              {
                name: 'value',
                path: '/name',
              },
              {
                name: 'parameter_id',
                path: '/location'
              }
            ]
          },
          {
            'name': 'hash_array_examlpe', # Хеш с массивом в значении (в данном примере к массиву применяется трансформация last_array_value
            'path': '/inventory/*',
            'transform': 'last_array_value',
            'hash_array': [ 
              {
                'name': 'item_name',
                'path': '/itemName'
              },
              {
                'name': 'price',
                'path': '/price',
              }
            ]
          }
        ]
JsonMapping.new({ objects: scheme, 'limitations': { }}).apply(j)
```