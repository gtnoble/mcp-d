/**
 * Schema validation system for MCP.
 *
 * This module provides a type-safe schema builder and validation system
 * for defining and validating JSON data structures. It is used primarily
 * for tool parameter validation in the MCP server.
 *
 * The module includes:
 * - Schema type definitions
 * - Builder pattern for schema construction
 * - Validation logic for different data types
 * - Constraint checking (ranges, patterns, etc.)
 *
 * Example:
 * ```d
 * // Define a schema for a person object
 * auto personSchema = SchemaBuilder.object()
 *     .addProperty("name", SchemaBuilder.string_().stringLength(1, 100))
 *     .addProperty("age", SchemaBuilder.integer().range(0, 120))
 *     .addProperty("email", SchemaBuilder.string_().setPattern(r"^[^@]+@[^@]+\.[^@]+$"))
 *     .addProperty("tags", SchemaBuilder.array(SchemaBuilder.string_()).optional());
 *
 * // Validate data against the schema
 * auto data = parseJSON(`{
 *     "name": "John Doe",
 *     "age": 30,
 *     "email": "john@example.com",
 *     "tags": ["developer", "d-lang"]
 * }`);
 *
 * try {
 *     personSchema.validate(data);
 *     writeln("Validation successful");
 * } catch (SchemaValidationError e) {
 *     writeln("Validation failed: ", e.msg);
 * }
 * ```
 */
module mcp.schema;

import std.json;
import std.traits : isNumeric, isIntegral;
import std.format : format;
import std.regex : regex, matchFirst;
import std.math : abs;
import std.math.operations : isClose;

/**
 * Schema type enumeration.
 *
 * Defines the basic data types supported by the schema system.
 */
enum SchemaType {
    string_,   // Note: underscore because 'string' is a D keyword
    number,
    integer,
    boolean,
    array,
    object,
    enum_      // String enumeration
}

/**
 * Exception thrown when schema validation fails.
 *
 * This exception provides information about validation failures,
 * including the path to the invalid element.
 */
class SchemaValidationError : Exception {
    private string path;

    this(string msg, string path = "", string file = __FILE__, size_t line = __LINE__) {
        this.path = path;
        super(format("%s at %s", msg, path.length > 0 ? path : "root"), file, line);
    }
}

/**
 * Schema builder and validator.
 *
 * The SchemaBuilder class provides a fluent interface for building
 * and validating JSON schemas. It supports all standard JSON Schema
 * types and constraints.
 */
class SchemaBuilder {
    private {
        SchemaType type;
        string description;
        bool required = true;

        // Object properties
        SchemaBuilder[string] properties;
        string[] requiredProps;
        bool additionalProperties = false;

        // Array properties
        SchemaBuilder elementType;
        size_t minItems;
        size_t maxItems;
        bool hasMinItems;
        bool hasMaxItems;
        bool uniqueItems;

        // Number constraints
        double minimumValue;   // Renamed from minimum
        double maximumValue;   // Renamed from maximum
        bool hasMin;
        bool hasMax;
        bool exclusiveMin;
        bool exclusiveMax;
        double multipleOfValue;  // Renamed from multipleOf
        bool hasMultipleOf;

        // String constraints
        size_t minLength;
        size_t maxLength;
        bool hasMinLength;
        bool hasMaxLength;
        string patternValue;     // Renamed from pattern
        bool hasPattern;

        // Enum values
        string[] enumValues;
    }

    private this() {}  // Private constructor, use static methods

    /**
     * Validates a JSON value against this schema.
     *
     * This method checks that the value matches the schema type
     * and satisfies all defined constraints.
     *
     * Params:
     *   value = The JSON value to validate
     *   path = The path to the current element (for error reporting)
     *
     * Throws:
     *   SchemaValidationError if validation fails
     */
    void validate(JSONValue value, string path = "") const {
        validateType(value, path);
        validateConstraints(value, path);
    }

    /**
     * Validates that the value matches the expected type.
     *
     * This method checks only the basic type (string, number, etc.)
     * without validating constraints.
     *
     * Params:
     *   value = The JSON value to validate
     *   path = The path to the current element (for error reporting)
     *
     * Throws:
     *   SchemaValidationError if the type doesn't match
     */
    private void validateType(JSONValue value, string path) const {
        final switch (type) {
            case SchemaType.string_:
            case SchemaType.enum_:
                if (value.type != JSONType.string) {
                    throw new SchemaValidationError("Expected string value", path);
                }
                break;

            case SchemaType.number:
                if (value.type != JSONType.float_ && value.type != JSONType.integer) {
                    throw new SchemaValidationError("Expected number value", path);
                }
                break;

            case SchemaType.integer:
                if (value.type != JSONType.integer) {
                    throw new SchemaValidationError("Expected integer value", path);
                }
                break;

            case SchemaType.boolean:
                if (value.type != JSONType.true_ && value.type != JSONType.false_) {
                    throw new SchemaValidationError("Expected boolean value", path);
                }
                break;

            case SchemaType.array:
                if (value.type != JSONType.array) {
                    throw new SchemaValidationError("Expected array value", path);
                }
                break;

            case SchemaType.object:
                if (value.type != JSONType.object) {
                    throw new SchemaValidationError("Expected object value", path);
                }
                break;
        }
    }

    /**
     * Validates type-specific constraints.
     *
     * This method checks constraints specific to each type, such as
     * string length, numeric ranges, array items, etc.
     *
     * Params:
     *   value = The JSON value to validate
     *   path = The path to the current element (for error reporting)
     *
     * Throws:
     *   SchemaValidationError if any constraint is violated
     */
    private void validateConstraints(JSONValue value, string path) const {
        final switch (type) {
            case SchemaType.string_:
                validateStringConstraints(value.str, path);
                break;

            case SchemaType.number:
            case SchemaType.integer:
                validateNumericConstraints(value, path);
                break;

            case SchemaType.boolean:
                // No additional constraints for boolean
                break;

            case SchemaType.array:
                validateArrayConstraints(value.array, path);
                break;

            case SchemaType.object:
                validateObjectConstraints(value, path);
                break;

            case SchemaType.enum_:
                validateEnumConstraints(value.str, path);
                break;
        }
    }

    private void validateStringConstraints(string value, string path) const {
        if (hasMinLength && value.length < minLength) {
            throw new SchemaValidationError(
                format("String length %d is less than minimum %d", value.length, minLength),
                path
            );
        }
        
        if (hasMaxLength && value.length > maxLength) {
            throw new SchemaValidationError(
                format("String length %d is greater than maximum %d", value.length, maxLength),
                path
            );
        }
        
        if (hasPattern) {
            auto pattern = regex(patternValue);
            if (!matchFirst(value, pattern)) {
                throw new SchemaValidationError(
                    format("String does not match pattern '%s'", patternValue),
                    path
                );
            }
        }
    }

    private void validateNumericConstraints(JSONValue value, string path) const {
        double numValue = value.type == JSONType.integer ? cast(double)value.integer : value.floating;

        if (hasMin) {
            if (exclusiveMin && numValue <= minimumValue) {
                throw new SchemaValidationError(
                    format("Value %g must be greater than %g", numValue, minimumValue),
                    path
                );
            } else if (!exclusiveMin && numValue < minimumValue) {
                throw new SchemaValidationError(
                    format("Value %g must be greater than or equal to %g", numValue, minimumValue),
                    path
                );
            }
        }

        if (hasMax) {
            if (exclusiveMax && numValue >= maximumValue) {
                throw new SchemaValidationError(
                    format("Value %g must be less than %g", numValue, maximumValue),
                    path
                );
            } else if (!exclusiveMax && numValue > maximumValue) {
                throw new SchemaValidationError(
                    format("Value %g must be less than or equal to %g", numValue, maximumValue),
                    path
                );
            }
        }

        if (hasMultipleOf) {
            auto remainder = numValue % multipleOfValue;
            if (!isClose(remainder, 0.0) && !isClose(remainder, multipleOfValue)) {
                throw new SchemaValidationError(
                    format("Value %g must be a multiple of %g", numValue, multipleOfValue),
                    path
                );
            }
        }
    }

    private void validateArrayConstraints(JSONValue[] array, string path) const {
        if (hasMinItems && array.length < minItems) {
            throw new SchemaValidationError(
                format("Array length %d is less than minimum %d", array.length, minItems),
                path
            );
        }

        if (hasMaxItems && array.length > maxItems) {
            throw new SchemaValidationError(
                format("Array length %d is greater than maximum %d", array.length, maxItems),
                path
            );
        }

        if (uniqueItems) {
            import std.algorithm : any;
            foreach (i, item1; array) {
                if (array[i + 1 .. $].any!(item2 => item1 == item2)) {
                    throw new SchemaValidationError("Array must have unique items", path);
                }
            }
        }

        foreach (i, item; array) {
            elementType.validate(item, format("%s[%d]", path, i));
        }
    }

    private void validateObjectConstraints(JSONValue value, string path) const {
        auto obj = value.object;

        // Check required properties
        foreach (prop; requiredProps) {
            if (prop !in obj) {
                throw new SchemaValidationError(
                    format("Missing required property '%s'", prop),
                    path
                );
            }
        }

        // Validate properties and check for additional
        foreach (key, val; obj) {
            auto propPath = path.length > 0 ? format("%s.%s", path, key) : key;
            
            auto propSchema = key in properties;
            if (propSchema !is null) {
                (*propSchema).validate(val, propPath);
            } else if (!additionalProperties) {
                throw new SchemaValidationError(
                    format("Additional property '%s' is not allowed", key),
                    path
                );
            }
        }
    }

    private void validateEnumConstraints(string value, string path) const {
        import std.algorithm : canFind;
        if (!enumValues.canFind(value)) {
            throw new SchemaValidationError(
                format("Value '%s' must be one of %s", value, enumValues),
                path
            );
        }
    }

    /**
     * Creates a string schema.
     *
     * Returns:
     *   A SchemaBuilder configured for string validation
     */
    static SchemaBuilder string_() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.string_;
        return builder;
    }

    /**
     * Creates a number schema.
     *
     * Returns:
     *   A SchemaBuilder configured for numeric validation
     */
    static SchemaBuilder number() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.number;
        return builder;
    }

    /**
     * Creates an integer schema.
     *
     * Returns:
     *   A SchemaBuilder configured for integer validation
     */
    static SchemaBuilder integer() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.integer;
        return builder;
    }

    /**
     * Creates a boolean schema.
     *
     * Returns:
     *   A SchemaBuilder configured for boolean validation
     */
    static SchemaBuilder boolean() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.boolean;
        return builder;
    }

    /**
     * Creates an array schema.
     *
     * Params:
     *   elementType = The schema for array elements
     *
     * Returns:
     *   A SchemaBuilder configured for array validation
     */
    static SchemaBuilder array(SchemaBuilder elementType) {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.array;
        builder.elementType = elementType;
        return builder;
    }

    /**
     * Creates an object schema.
     *
     * Returns:
     *   A SchemaBuilder configured for object validation
     */
    static SchemaBuilder object() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.object;
        return builder;
    }

    /**
     * Creates a string enumeration schema.
     *
     * Params:
     *   values = The allowed string values
     *
     * Returns:
     *   A SchemaBuilder configured for enum validation
     */
    static SchemaBuilder enum_(string[] values...) {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.enum_;
        builder.enumValues = values;
        return builder;
    }

    /**
     * Sets the schema description.
     *
     * Params:
     *   desc = The description text
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     */
    SchemaBuilder setDescription(string desc) {
        description = desc;
        return this;
    }

    /**
     * Makes a property optional.
     *
     * By default, all properties are required. This method marks
     * a property as optional.
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     */
    SchemaBuilder optional() {
        required = false;
        return this;
    }

    /**
     * Adds a property to an object schema.
     *
     * Params:
     *   name = The property name
     *   prop = The property schema
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     *
     * Throws:
     *   Assertion error if this is not an object schema
     */
    SchemaBuilder addProperty(string name, SchemaBuilder prop) {
        assert(type == SchemaType.object, "Can only add properties to object schema");
        properties[name] = prop;
        if (prop.required) {
            requiredProps ~= name;
        }
        return this;
    }

    /**
     * Controls whether additional properties are allowed.
     *
     * By default, additional properties are not allowed in objects.
     *
     * Params:
     *   allow = Whether to allow additional properties
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     *
     * Throws:
     *   Assertion error if this is not an object schema
     */
    SchemaBuilder allowAdditional(bool allow) {
        assert(type == SchemaType.object, "Additional properties only apply to object schema");
        additionalProperties = allow;
        return this;
    }

    /**
     * Sets array length constraints.
     *
     * Params:
     *   min = Minimum array length
     *   max = Maximum array length
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     *
     * Throws:
     *   Assertion error if this is not an array schema
     */
    SchemaBuilder length(size_t min, size_t max) {
        assert(type == SchemaType.array, "Length constraints only apply to array schema");
        minItems = min;
        maxItems = max;
        hasMinItems = hasMaxItems = true;
        return this;
    }

    /**
     * Requires array items to be unique.
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     *
     * Throws:
     *   Assertion error if this is not an array schema
     */
    SchemaBuilder unique() {
        assert(type == SchemaType.array, "Unique constraint only applies to array schema");
        uniqueItems = true;
        return this;
    }

    /**
     * Sets numeric range constraints.
     *
     * Params:
     *   min = Minimum value (inclusive)
     *   max = Maximum value (inclusive)
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     *
     * Throws:
     *   Assertion error if this is not a numeric schema
     */
    SchemaBuilder range(T)(T min, T max) if (isNumeric!T) {
        assert(type == SchemaType.number || type == SchemaType.integer,
               "Range constraints only apply to numeric schema");
        minimumValue = cast(double)min;
        maximumValue = cast(double)max;
        hasMin = hasMax = true;
        if (isIntegral!T) {
            type = SchemaType.integer;
        }
        return this;
    }

    /**
     * Sets exclusive numeric range constraints.
     *
     * Params:
     *   min = Minimum value (exclusive)
     *   max = Maximum value (exclusive)
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     *
     * Throws:
     *   Assertion error if this is not a numeric schema
     */
    SchemaBuilder exclusiveRange(T)(T min, T max) if (isNumeric!T) {
        range(min, max);
        exclusiveMin = exclusiveMax = true;
        return this;
    }

    /**
     * Sets a "multiple of" constraint for numeric values.
     *
     * Params:
     *   value = The value that numbers must be a multiple of
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     *
     * Throws:
     *   Assertion error if this is not a numeric schema
     */
    SchemaBuilder setMultipleOf(double value) {
        assert(type == SchemaType.number || type == SchemaType.integer,
               "Multiple of constraint only applies to numeric schema");
        multipleOfValue = value;
        hasMultipleOf = true;
        return this;
    }

    /**
     * Sets string length constraints.
     *
     * Params:
     *   min = Minimum string length
     *   max = Maximum string length
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     *
     * Throws:
     *   Assertion error if this is not a string schema
     */
    SchemaBuilder stringLength(size_t min, size_t max) {
        assert(type == SchemaType.string_, "String length only applies to string schema");
        minLength = min;
        maxLength = max;
        hasMinLength = hasMaxLength = true;
        return this;
    }

    /**
     * Sets a regular expression pattern for string validation.
     *
     * Params:
     *   regex = The regular expression pattern
     *
     * Returns:
     *   This SchemaBuilder for method chaining
     *
     * Throws:
     *   Assertion error if this is not a string schema
     */
    SchemaBuilder setPattern(string regex) {
        assert(type == SchemaType.string_, "Pattern only applies to string schema");
        patternValue = regex;
        hasPattern = true;
        return this;
    }

    /**
     * Converts the schema to JSON format.
     *
     * This method generates a JSON Schema representation of this schema.
     *
     * Returns:
     *   A JSONValue containing the schema definition
     */
    JSONValue toJSON() const {
        JSONValue result;

        // Base schema
        result = [
            "type": schemaTypeToString(type)
        ];

        if (description.length > 0) {
            result["description"] = description;
        }

        // Type-specific properties
        final switch (type) {
            case SchemaType.string_:
                if (hasMinLength) result["minLength"] = minLength;
                if (hasMaxLength) result["maxLength"] = maxLength;
                if (hasPattern) result["pattern"] = patternValue;
                break;

            case SchemaType.number:
            case SchemaType.integer:
                if (hasMin) {
                    result[exclusiveMin ? "exclusiveMinimum" : "minimum"] = minimumValue;
                }
                if (hasMax) {
                    result[exclusiveMax ? "exclusiveMaximum" : "maximum"] = maximumValue;
                }
                if (hasMultipleOf) result["multipleOf"] = multipleOfValue;
                break;

            case SchemaType.boolean:
                break;

            case SchemaType.array:
                result["items"] = elementType.toJSON();
                if (hasMinItems) result["minItems"] = minItems;
                if (hasMaxItems) result["maxItems"] = maxItems;
                if (uniqueItems) result["uniqueItems"] = true;
                break;

            case SchemaType.object:
                if (properties.length > 0) {
                    JSONValue[string] props;
                    foreach (name, prop; properties) {
                        props[name] = prop.toJSON();
                    }
                    result["properties"] = props;
                    if (requiredProps.length > 0) {
                        result["required"] = requiredProps;
                    }
                }
                // Only add additionalProperties when it's false (JSON Schema default is true)
                if (!additionalProperties) {
                    result["additionalProperties"] = false;
                }
                break;

            case SchemaType.enum_:
                result["enum"] = enumValues;
                break;
        }

        return result;
    }

private:
    static string schemaTypeToString(SchemaType type) {
        final switch (type) {
            case SchemaType.string_: return "string";
            case SchemaType.number: return "number";
            case SchemaType.integer: return "integer";
            case SchemaType.boolean: return "boolean";
            case SchemaType.array: return "array";
            case SchemaType.object: return "object";
            case SchemaType.enum_: return "string";  // Enums are string-based
        }
    }
}
