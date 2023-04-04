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
            'name': 'items_all_examlpe', # массив из всех элементов одного уровня с параметризацией
            'path': '/',
            'exclude': ['storeId', 'weeklyVisitors'],
            'items_all':[
              [
                {
                  "name": "value",
                  "path": "/"
                },
                {
                  "name": "parameter_id",
                  "default": "%%[%key_name%]%%"
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
          },
          {
            'name': 'merged',
            'merge_arrays': [
              '/employees', '/inventory'
            ]
          }
        ]
JsonMapping.new({ objects: scheme, 'limitations': { }}).apply(j)

{"name"=>"Trader Joe's",
 "profits"=>0,
 "attributes_examlpe"=>[{"item_name"=>"Apples", "price"=>0.5}, {"item_name"=>"Oranges", "price"=>2}, {"item_name"=>"Bag of Carrots", "price"=>1.5}],
 "items_examlpe"=>[{"value"=>"Trader Joe's", "parameter_id"=>"Berkeley, California"}],
 "items_all_examlpe"=>
  [{"value"=>"Trader Joe's", "parameter_id"=>"%%name%%"},
   {"value"=>"Berkeley, California", "parameter_id"=>"%%location%%"},
   {"value"=>[{"name"=>"Jim Shoes"}, {"name"=>"Kay Oss"}], "parameter_id"=>"%%employees%%"},
   {"value"=>[{"itemName"=>"Apples", "price"=>0.5, "unit"=>"lb"}, {"itemName"=>"Oranges", "price"=>2, "unit"=>"lb"}, {"itemName"=>"Bag of Carrots", "price"=>1.5, "unit"=>"count"}],
    "parameter_id"=>"%%inventory%%"}],
 "hash_examlpe"=>{"value"=>"Trader Joe's", "parameter_id"=>"Berkeley, California"},
 "hash_array_examlpe"=>{"item_name"=>"Bag of Carrots", "price"=>1.5},
 "merged"=>
  [{"name"=>"Jim Shoes"},
   {"name"=>"Kay Oss"},
   {"itemName"=>"Apples", "price"=>0.5, "unit"=>"lb"},
   {"itemName"=>"Oranges", "price"=>2, "unit"=>"lb"},
   {"itemName"=>"Bag of Carrots", "price"=>1.5, "unit"=>"count"}]}
```
### 2. Вложенные атрибуты
Позволяет завернуть результат в хеш
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
            name: 'Store',
            nested: [
              {
                name: 'name',
                path: '/name'
              },
              {
                name: 'location',
                path: '/location'
              }
            ]
          }
         ]
JsonMapping.new({ objects: scheme, 'limitations': { }}).apply(j)
```