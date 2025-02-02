require 'yaml'.freeze
require 'logger'.freeze
require 'conditions'.freeze

##
# Stores and applies a mapping to an input ruby Hash
class JsonMapping
  ##
  # Thrown when a transform is not found or not callable
  class TransformError < StandardError; end
  ##
  # Thrown when parsing an invalid path
  class PathError < StandardError; end
  ##
  # Thrown when the YAML transform is not formatted properly
  class FormatError < StandardError; end

  ##
  # @param [String] schema_path The path to the YAML schema
  # @param [Hash] transforms A hash of callable objects (Procs/Lambdas). Keys must match transform names specified in YAML
  def initialize(json_schema, transforms = {})
    schema = json_schema.deep_stringify_keys

    @conditions = (schema['conditions'] || {}).map do |key, value|
      [key, Object.const_get("Conditions::#{value['class']}").new(value['predicate'])]
    end.to_h
    @limitations = schema['limitations'].to_h

    @object_schemas = schema['objects']
    @transforms = transforms.merge(default_transforms)
    @logger = Logger.new($stdout)
  end

  def default_transforms
    {
      'to_array' => -> (val) { Array.wrap(val).uniq.compact },
      'downcase' => -> (val) { val.to_s.downcase },
      'upcase' => -> (val) { val.to_s.upcase },
      'to_hash' => -> (array) { Array.wrap(array).uniq.collect{ |item| [item['key'], item['value']]}.to_h },
      'first_array_value' => -> (array) { array.is_a?(Array) ? array.first : array },
      'last_array_value' => -> (array) { array.is_a?(Array) ? array.last : array },
      'max_array_value' => -> (array) { array.is_a?(Array) ? array.max : array },
      'max_datatime_array_value' => -> (array) { array.is_a?(Array) ? array.collect{|date_str| DateTime.parse(date_str)}.max : array },
      'uniq_array' => -> (array) { array.is_a?(Array) ? array.uniq : array },
      'array_size' => -> (array) { array.is_a?(Array) ? array.size : 0 },
      'hashes_array_filter' => -> (array, keys, value) { array.is_a?(Array) ? array.select{|h| h.dig(*keys.split('*')) == value } : array },
      'hash_value' => -> (hash, key) { hash.is_a?(Hash) ? hash[key] : hash },
      'hash_values' => -> (hash) { hash.is_a?(Hash) ? hash.values : hash },
      'hash_keys' => -> (hash) { hash.is_a?(Hash) ? hash.keys : hash },
      'array_select_regex' => -> (array, regex) {
        array.is_a?(Array) ? array.select { |val| val.to_s.match?(Regexp.new(regex))
      }
 : [] },
      'json_parse' => -> (value) { value.present? ? begin JSON.parse(value) rescue value end : {} }
    }
  end

  def apply_transforms(transform, values)
    return values unless transform

    if transform.is_a?(Array)
      transform.each do |t|
        transform_with_params = t.split('|')
        values = @transforms[transform_with_params.first].call(values, *transform_with_params[1..-1])
      end
    else
      transform_with_params = transform.split('|')
      values = @transforms[transform_with_params.first].call(values, *transform_with_params[1..-1])
    end
    values
  end

  ##
  # @param [Hash] input_hash A ruby hash onto which the schema should be applied
  # @return [Array] An array of output hashes representing the mapped objects
  def apply(input_hash)
    raise FormatError, 'Must define objects under the \'objects\' name' if @object_schemas.nil?
    normalized_input_hash = input_hash.deep_stringify_keys.deep_transform_keys(&:downcase)
    result = @object_schemas.map { |schema| parse_object(normalized_input_hash, schema) }.reduce(&:merge)
    return result['unwrap'] if result.is_a?(Hash) and result.include?('unwrap')

    result
  end

  private

  ##
  # Maps an object schema to an object in the output
  # @param [Hash] input_hash The hash onto which the schema should be mapped
  # @param [Hash] schema A hash representing the schema which should be applied to the input
  # Raises +FormatError+ if +schema+ is not a +Hash+ or has no key +name+
  # @return [Hash] The output object
  def parse_object(input_hash, schema, parameters = {})
    raise FormatError, "Object should be a hash: #{schema}" unless schema.is_a? Hash
    raise FormatError, "Object needs a name: #{schema}" unless schema.key?('name')

    output = {}
    # Its an object
    if schema.key?('attributes')
      output[schema['name']] = schema['default']

      object_hash = parse_path(input_hash, schema['path'])
      return output if object_hash.nil?

      unless object_hash.is_a? Array
        object_hash = [object_hash]
      end

      attrs = []
      object_hash.each do |obj|
        item_object = schema['conditions'] ? apply_conditions(obj, schema['conditions']) : obj
        next unless item_object

        valid_hash = true
        attributes_hash = {}
        schema['attributes'].each do |attribute|
          attr_hash = parse_object(item_object, attribute)
          valid_hash = false if attribute['require'] && attr_hash[attribute['name']].blank?
          attributes_hash = attributes_hash.merge(attr_hash)
        end

        attrs << attributes_hash if !limited?(attributes_hash, schema['limits']) && valid_hash
      end

      attribute_values = attrs.length == 1 && schema['path'][-1] != '*' ? attrs[0] : attrs
      attribute_values = apply_transforms(schema['transform'], attribute_values)
      output[schema['name']] = attribute_values
    elsif schema.key?('nested')
      nested_hash = {}
      schema['nested'].each do |attribute|
        nested_hash.merge! map_value(input_hash, attribute)
      end
      output[schema['name']] = nested_hash
    elsif schema.key?('items')
      output[schema['name']] = schema['default'].to_a

      object_hash = parse_path(input_hash, schema['path'])
      return output if object_hash.nil?

      unless object_hash.is_a? Array
        object_hash = [object_hash]
      end

      items_values = []
      object_hash.each do |obj|
        item_object = schema['conditions'] ? apply_conditions(obj, schema['conditions']) : obj
        next unless item_object

        attributes_hash = {}
        schema['items'].each do |item|
          valid_hash = true
          item.each do |attribute|
            attr_hash = parse_object(item_object, attribute)
            valid_hash = false if attribute['require'] && attr_hash[attribute['name']].blank?
            attributes_hash = attributes_hash.merge(attr_hash)
          end
          items_values << attributes_hash if !limited?(attributes_hash, schema['limits']) && valid_hash
        end
      end
      items_values = apply_transforms(schema['transform'], items_values)
      output[schema['name']] = items_values
    elsif schema.key?('items_all')
      exclude = schema['exclude'].to_a.map(&:downcase)
      output[schema['name']] = schema['default'].to_a

      object_hash = parse_path(input_hash, schema['path'])
      return output if object_hash.nil?

      unless object_hash.is_a? Array
        object_hash = [object_hash]
      end

      items_values = []
      object_hash.each do |obj|
        obj.each do |key, value|
          next if exclude.include?(key.downcase)

          attributes_hash = {}
          schema['items_all'].each do |item|
            valid_hash = true
            item.each do |attribute|
              attr_hash = parse_object(value, attribute, {'key_name' => key[0..50]})
              valid_hash = false if attribute['require'] && attr_hash[attribute['name']].blank?
              attributes_hash = attributes_hash.merge(attr_hash)
            end
            items_values << attributes_hash if !limited?(attributes_hash, schema['limits']) && valid_hash
          end
        end
      end
      items_values = apply_transforms(schema['transform'], items_values)
      output[schema['name']] = items_values
    elsif schema.key?('hash')
      output[schema['name']] = schema['default'].to_a

      object_hash = parse_path(input_hash, schema['path'])
      return output if object_hash.nil?

      unless object_hash.is_a? Array
        object_hash = [object_hash]
      end

      items_values = {}
      object_hash.each do |obj|
        item_object = schema['conditions'] ? apply_conditions(obj, schema['conditions']) : obj
        next unless item_object

        schema['hash'].each do |item|
          attr_hash = parse_object(item_object, item)
          items_values.merge!(attr_hash)
        end
      end
      output[schema['name']] = items_values
    elsif schema.key?('array')
      output[schema['name']] = schema['default'].to_a

      array = []
      schema['array'].each do |item|
        array << parse_object(input_hash, item)&.values
      end
      output[schema['name']] = apply_transforms(schema['transform'], array.flatten.uniq.compact)
    elsif schema.key?('hash_array')
      output[schema['name']] = schema['default'].to_a
      object_hash = parse_path(input_hash, schema['path'])
      return output if object_hash.nil?

      unless object_hash.is_a? Array
        object_hash = [object_hash]
      end

      items_values = {}
      object_hash.each do |obj|
        schema['hash_array'].each do |item|
          attr_hash = parse_object(obj, item)
          
          key = attr_hash.keys.first
          items_values[key] = [] unless items_values[key]
          items_values[key] += attr_hash.values
        end
      end

      items_values = items_values.each_with_object({}) do |(k, v), a|
                      v.uniq!
                      v = apply_transforms(schema['transform'], v)
                      a[k] = v
                    end
      output[schema['name']] = items_values
    elsif schema.key?('merge_arrays')
      merged = []
      schema['merge_arrays'].each do |path|
        merged += parse_path(input_hash, path).to_a
      end
      output[schema['name']] = apply_transforms(schema['transform'], merged.uniq)
    else # Its a value
      output = map_value(input_hash, schema, parameters)
    end

    output
  end

  def parametrize(str, parameters)
    return nil if str.nil?
    return str if parameters.empty?
    return str unless str.is_a?(String)

    res = str
    parameters.each do |key, value|
      res = str.gsub("[%#{key}%]", value.downcase)
    end
    res
  end

  def limited?(hash, limits)
    return false if @limitations.empty? || limits.blank?

    limits.each do |limit|
      next if limit.blank?
      hash_key = limit.keys.first
      limit_key = limit.values.first

      v = hash[hash_key]
      next unless v

      return true if @limitations[limit_key].is_a?(Array) and @limitations[limit_key].exclude?(v)
    end
    false
  end

  ##
  # Maps a schema to a single field in the output schema
  # @param [Hash] input_hash The input hash to be mapped
  # @param [Hash] schema The schema which should be applied
  # @return [Hash] A Hash which represents the applied schema
  def map_value(input_hash, schema, parameters = {})
    raise FormatError, "Schema should be a hash: #{schema}" unless schema.is_a? Hash

    output = {}
    output[schema['name']] = parametrize(schema['default'], parameters)
    return output if schema['path'].nil?

    value = parse_path(input_hash, schema['path'])
    return output if value.nil?

    if schema.key?('conditions')
      value = apply_conditions(value, schema['conditions']) || output[schema['name']]
    end

    if schema.key?('transform') && value != output[schema['name']]
      value = apply_transforms(schema['transform'], value)
    end

    output[schema['name']] = parametrize(value, parameters)
    output
  end

  ##
  # @param [Hash] input_hash The input hash
  # @param [String] path The path at which to grab the value
  # @return [Any] The value at the particular path
  def parse_path(input_hash, path)
    raise ArgumentError, "path must be string, not #{path.class}" unless path.is_a? String

    parts = path.split('/')
    value = input_hash
    parts.each_with_index do |part, idx|
      if value.nil?
        @logger.warn("Could not find #{path} in #{input_hash}")
        break
      end
      if part == '*'
        raise PathError, "#{parts[0, idx].join('/')} in #{input_hash} is not an array" unless value.is_a? Array


        return value.map { |obj| parse_path(obj, parts[idx + 1..-1].join('/')) }
      else
        next if part.empty?

        if value.is_a? Array
          part = part.to_i

          if part >= value.length
            @logger.warn("Index went out of bounds while parsing #{path} in #{input_hash}")
            value = nil
            break
          end
        end

        value = value[part]
      end
    end
    value
  end

  ##
  # Applies conditions to a value
  # @param [Any] value A value to compare the condition predicates against
  # @param [Array] conds An array of conditions
  # @return [Array] If multiple conditions are satisfied
  # @return [Any] If one condition is satisfied
  # @return [nil] If no conditions are satisfied
  def apply_conditions(value, conds)
    output = []
    conds.each do |cond|
      input_val = value
      raise FormatError, "Conditions are a hash: #{cond}" unless cond.is_a? Hash
      raise Conditions::ConditionError, "Unknown condition named #{cond['name']}" unless @conditions.key?(cond['name'])

      condition = @conditions[cond['name']]

      input_val = [input_val] unless input_val.is_a? Array
      input_val = input_val.select do |x|
        x = parse_path(x, cond['field']) if cond.key?('field')
        condition.apply(x)
      end

      next if input_val.empty?

      # Maintain the original data-type of the value (i.e Array or single element)
      input_val = input_val[0] if input_val.length == 1 && !value.is_a?(Array)
      output << (cond['output'] || input_val)
    end

    return (output.length == 1 ? output[0] : output) unless output.empty?
  end
end
