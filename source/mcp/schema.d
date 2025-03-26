module mcp.schema;

import std.json;
import std.traits : isNumeric, isIntegral;
import std.format : format;
import std.regex : regex, matchFirst;

/// Schema type enumeration
enum SchemaType {
    string_,   // Note: underscore because 'string' is a D keyword
    number,
    integer,
    boolean,
    array,
    object,
    enum_      // String enumeration
}

/// Schema validation error
class SchemaValidationError : Exception {
    private string path;

    this(string msg, string path = "", string file = __FILE__, size_t line = __LINE__) {
        this.path = path;
        super(format("%s at %s", msg, path.length > 0 ? path : "root"), file, line);
    }
}

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

    /// Validate a JSON value against this schema
    void validate(JSONValue value, string path = "") const {
        validateType(value, path);
        validateConstraints(value, path);
    }

    /// Validate type matching
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

    /// Validate type-specific constraints
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
            import std.math : abs, isClose;
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

    /// Create string schema
    static SchemaBuilder string_() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.string_;
        return builder;
    }

    /// Create number schema
    static SchemaBuilder number() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.number;
        return builder;
    }

    /// Create integer schema
    static SchemaBuilder integer() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.integer;
        return builder;
    }

    /// Create boolean schema
    static SchemaBuilder boolean() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.boolean;
        return builder;
    }

    /// Create array schema
    static SchemaBuilder array(SchemaBuilder elementType) {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.array;
        builder.elementType = elementType;
        return builder;
    }

    /// Create object schema
    static SchemaBuilder object() {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.object;
        return builder;
    }

    /// Create string enumeration schema
    static SchemaBuilder enum_(string[] values...) {
        auto builder = new SchemaBuilder();
        builder.type = SchemaType.enum_;
        builder.enumValues = values;
        return builder;
    }

    /// Set description
    SchemaBuilder setDescription(string desc) {
        description = desc;
        return this;
    }

    /// Make property optional
    SchemaBuilder optional() {
        required = false;
        return this;
    }

    /// Add object property
    SchemaBuilder addProperty(string name, SchemaBuilder prop) {
        assert(type == SchemaType.object, "Can only add properties to object schema");
        properties[name] = prop;
        if (prop.required) {
            requiredProps ~= name;
        }
        return this;
    }

    /// Allow additional properties
    SchemaBuilder allowAdditional(bool allow) {
        assert(type == SchemaType.object, "Additional properties only apply to object schema");
        additionalProperties = allow;
        return this;
    }

    /// Set array length constraints
    SchemaBuilder length(size_t min, size_t max) {
        assert(type == SchemaType.array, "Length constraints only apply to array schema");
        minItems = min;
        maxItems = max;
        hasMinItems = hasMaxItems = true;
        return this;
    }

    /// Require unique array items
    SchemaBuilder unique() {
        assert(type == SchemaType.array, "Unique constraint only applies to array schema");
        uniqueItems = true;
        return this;
    }

    /// Set numeric range
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

    /// Set exclusive numeric range
    SchemaBuilder exclusiveRange(T)(T min, T max) if (isNumeric!T) {
        range(min, max);
        exclusiveMin = exclusiveMax = true;
        return this;
    }

    /// Set multiple of constraint
    SchemaBuilder setMultipleOf(double value) {
        assert(type == SchemaType.number || type == SchemaType.integer,
               "Multiple of constraint only applies to numeric schema");
        multipleOfValue = value;
        hasMultipleOf = true;
        return this;
    }

    /// Set string length constraints
    SchemaBuilder stringLength(size_t min, size_t max) {
        assert(type == SchemaType.string_, "String length only applies to string schema");
        minLength = min;
        maxLength = max;
        hasMinLength = hasMaxLength = true;
        return this;
    }

    /// Set string pattern
    SchemaBuilder setPattern(string regex) {
        assert(type == SchemaType.string_, "Pattern only applies to string schema");
        patternValue = regex;
        hasPattern = true;
        return this;
    }

    /// Convert schema to JSON
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
