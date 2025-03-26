module mcp.schema_test;

import mcp.schema;
import std.json;
import std.algorithm : canFind;
import std.exception : assertThrown;

// Helper function to check if a string is in a JSONValue array
private bool hasRequiredProperty(JSONValue[] array, string property) {
    return array.canFind(JSONValue(property));
}

// Basic Schema Creation Tests
unittest {
    // Test string schema
    auto strSchema = SchemaBuilder.string_()
        .setDescription("A test string");
    auto strJson = strSchema.toJSON();
    assert(strJson["type"].str == "string");
    assert(strJson["description"].str == "A test string");

    // Test number schema
    auto numSchema = SchemaBuilder.number()
        .setDescription("A test number");
    auto numJson = numSchema.toJSON();
    assert(numJson["type"].str == "number");
    assert(numJson["description"].str == "A test number");

    // Test integer schema
    auto intSchema = SchemaBuilder.integer()
        .setDescription("A test integer");
    auto intJson = intSchema.toJSON();
    assert(intJson["type"].str == "integer");
    assert(intJson["description"].str == "A test integer");

    // Test boolean schema
    auto boolSchema = SchemaBuilder.boolean()
        .setDescription("A test boolean");
    auto boolJson = boolSchema.toJSON();
    assert(boolJson["type"].str == "boolean");
    assert(boolJson["description"].str == "A test boolean");

    // Test enum schema
    auto enumSchema = SchemaBuilder.enum_("red", "green", "blue")
        .setDescription("A test enum");
    auto enumJson = enumSchema.toJSON();
    assert(enumJson["type"].str == "string");
    assert(enumJson["enum"].array.length == 3);
    assert(enumJson["enum"].array[0].str == "red");
    assert(enumJson["description"].str == "A test enum");
}

// Object Schema Tests
unittest {
    auto objSchema = SchemaBuilder.object()
        .setDescription("A test object")
        .addProperty("name", SchemaBuilder.string_())
        .addProperty("age", SchemaBuilder.integer().optional())
        .addProperty("tags", SchemaBuilder.array(SchemaBuilder.string_()))
        .allowAdditional(false);

    auto json = objSchema.toJSON();
    assert(json["type"].str == "object");
    assert(json["description"].str == "A test object");
    assert(json["properties"]["name"]["type"].str == "string");
    assert(json["properties"]["age"]["type"].str == "integer");
    assert(json["properties"]["tags"]["type"].str == "array");
    assert(json["properties"]["tags"]["items"]["type"].str == "string");
    // Verify required properties
    assert("required" in json);  // Check required field exists
    auto required = json["required"].array;
    assert(required.length == 2); // name and tags are required, age is optional
    assert(hasRequiredProperty(required, "name"));
    assert(hasRequiredProperty(required, "tags"));
    assert(!hasRequiredProperty(required, "age"));
    assert("additionalProperties" in json);
}

// Array Schema Tests
unittest {
    auto arraySchema = SchemaBuilder.array(SchemaBuilder.number())
        .setDescription("A test array")
        .length(1, 5)
        .unique();

    auto json = arraySchema.toJSON();
    assert(json["type"].str == "array");
    assert(json["items"]["type"].str == "number");
    assert(json["minItems"].uinteger == 1);
    assert(json["maxItems"].uinteger == 5);
    assert(json["uniqueItems"].boolean == true);
}

// Numeric Constraints Tests
unittest {
    // Test range constraints
    auto numSchema = SchemaBuilder.number()
        .range(0.0, 100.0)
        .setMultipleOf(0.5);

    auto numJson = numSchema.toJSON();
    assert(numJson["minimum"].floating == 0.0);
    assert(numJson["maximum"].floating == 100.0);
    assert(numJson["multipleOf"].floating == 0.5);

    // Test exclusive range
    auto exclusiveSchema = SchemaBuilder.integer()
        .exclusiveRange(0, 10);

    auto exclusiveJson = exclusiveSchema.toJSON();
    assert(exclusiveJson["exclusiveMinimum"].floating == 0.0);
    assert(exclusiveJson["exclusiveMaximum"].floating == 10.0);
}

// String Constraints Tests
unittest {
    auto strSchema = SchemaBuilder.string_()
        .stringLength(1, 100)
        .setPattern(`^[A-Za-z0-9]+$`);

    auto json = strSchema.toJSON();
    assert(json["type"].str == "string");
    assert(json["minLength"].uinteger == 1);
    assert(json["maxLength"].uinteger == 100);
    assert(json["pattern"].str == `^[A-Za-z0-9]+$`);
}

// Complex Nested Schema Tests
unittest {
    // Create a complex user profile schema
    auto profileSchema = SchemaBuilder.object()
        .setDescription("User profile")
        .addProperty("id", SchemaBuilder.string_().setPattern(`^[A-Za-z0-9-]+$`))
        .addProperty("name", SchemaBuilder.object()
            .addProperty("first", SchemaBuilder.string_().stringLength(1, 50))
            .addProperty("last", SchemaBuilder.string_().stringLength(1, 50)))
        .addProperty("age", SchemaBuilder.integer().range(0, 150).optional())
        .addProperty("email", SchemaBuilder.string_().setPattern(`^[^@]+@[^@]+\.[^@]+$`))
        .addProperty("roles", SchemaBuilder.array(SchemaBuilder.enum_("user", "admin", "moderator"))
            .length(1, 3)
            .unique())
        .addProperty("settings", SchemaBuilder.object()
            .addProperty("theme", SchemaBuilder.enum_("light", "dark").optional())
            .addProperty("notifications", SchemaBuilder.boolean())
            .allowAdditional(true));

    auto json = profileSchema.toJSON();
    
    // Verify basic structure
    assert(json["type"].str == "object");
    assert(json["properties"]["id"]["pattern"].str == `^[A-Za-z0-9-]+$`);
    
    // Verify nested name object
    assert(json["properties"]["name"]["type"].str == "object");
    assert(json["properties"]["name"]["properties"]["first"]["maxLength"].uinteger == 50);
    
    // Verify optional age
    assert(json["properties"]["age"]["type"].str == "integer");
    assert(!hasRequiredProperty(json["required"].array, "age"));
    
    // Verify roles array
    assert(json["properties"]["roles"]["type"].str == "array");
    assert(json["properties"]["roles"]["items"]["enum"].array.length == 3);
    assert(json["properties"]["roles"]["uniqueItems"].boolean == true);
    
    // Verify settings object
    assert(json["properties"]["settings"]["type"].str == "object");
    assert(!("additionalProperties" in json["properties"]["settings"]));  // Since it defaults to true
    auto settingsRequired = json["properties"]["settings"]["required"].array;
    assert(!hasRequiredProperty(settingsRequired, "theme"));
    assert(hasRequiredProperty(settingsRequired, "notifications"));
}

// Validation Tests
unittest {
    // Test string validation
    auto strSchema = SchemaBuilder.string_()
        .stringLength(2, 5)
        .setPattern(`^[A-Z]+$`);
    
    // Valid cases
    strSchema.validate(JSONValue("ABC")); // Should pass
    
    // Invalid cases
    assertThrown!SchemaValidationError(strSchema.validate(JSONValue("A"))); // Too short
    assertThrown!SchemaValidationError(strSchema.validate(JSONValue("ABCDEF"))); // Too long
    assertThrown!SchemaValidationError(strSchema.validate(JSONValue("abc"))); // Wrong pattern
    assertThrown!SchemaValidationError(strSchema.validate(JSONValue(123))); // Wrong type
    
    // Test number validation
    auto numSchema = SchemaBuilder.number()
        .range(0.0, 100.0)
        .setMultipleOf(0.5);
    
    // Valid cases
    numSchema.validate(JSONValue(50.0)); // Should pass
    numSchema.validate(JSONValue(1.5)); // Should pass
    
    // Invalid cases
    assertThrown!SchemaValidationError(numSchema.validate(JSONValue(-1.0))); // Below range
    assertThrown!SchemaValidationError(numSchema.validate(JSONValue(101.0))); // Above range
    assertThrown!SchemaValidationError(numSchema.validate(JSONValue(1.25))); // Not multiple
    assertThrown!SchemaValidationError(numSchema.validate(JSONValue("50"))); // Wrong type
    
    // Test array validation
    auto arraySchema = SchemaBuilder.array(SchemaBuilder.number().range(0, 10))
        .length(2, 4)
        .unique();
    
    // Valid cases
    arraySchema.validate(JSONValue([1, 2, 3])); // Should pass
    
    // Invalid cases
    assertThrown!SchemaValidationError(arraySchema.validate(JSONValue([1]))); // Too short
    assertThrown!SchemaValidationError(arraySchema.validate(JSONValue([1, 2, 3, 4, 5]))); // Too long
    assertThrown!SchemaValidationError(arraySchema.validate(JSONValue([1, 1, 2]))); // Not unique
    assertThrown!SchemaValidationError(arraySchema.validate(JSONValue([1, 11, 2]))); // Out of range
    assertThrown!SchemaValidationError(arraySchema.validate(JSONValue(123))); // Not an array
    
    // Test object validation
    auto objSchema = SchemaBuilder.object()
        .addProperty("name", SchemaBuilder.string_().stringLength(1, 50))
        .addProperty("age", SchemaBuilder.integer().range(0, 150))
        .addProperty("tags", SchemaBuilder.array(SchemaBuilder.string_()).optional());
    
    // Valid cases
    objSchema.validate(JSONValue([
        "name": "John",
        "age": 30
    ])); // Should pass
    
    objSchema.validate(JSONValue([
        "name": "John",
        "age": 30,
        "tags": ["a", "b"]
    ])); // Should pass with optional field
    
    // Invalid cases
    assertThrown!SchemaValidationError(objSchema.validate(JSONValue([
        "name": "John"
    ]))); // Missing required field
    
    assertThrown!SchemaValidationError(objSchema.validate(JSONValue([
        "name": "John",
        "age": "30" // Wrong type for age
    ])));
    
    assertThrown!SchemaValidationError(objSchema.validate(JSONValue([
        "name": "John",
        "age": 30,
        "extra": "field" // Additional field not allowed
    ])));
}

// Edge Case Tests
unittest {
    // Test empty object schema
    auto emptyObj = SchemaBuilder.object();
    auto emptyJson = emptyObj.toJSON();
    assert(emptyJson["type"].str == "object");
    assert(!("properties" in emptyJson));
    assert(!("required" in emptyJson));
    
    // Test array with empty object
    auto arrayOfObjects = SchemaBuilder.array(SchemaBuilder.object());
    auto arrayJson = arrayOfObjects.toJSON();
    assert(arrayJson["type"].str == "array");
    assert(arrayJson["items"]["type"].str == "object");
    
    // Test deeply nested arrays
    auto nestedArray = SchemaBuilder.array(
        SchemaBuilder.array(
            SchemaBuilder.array(
                SchemaBuilder.string_()
            )
        )
    );
    auto nestedJson = nestedArray.toJSON();
    assert(nestedJson["type"].str == "array");
    assert(nestedJson["items"]["type"].str == "array");
    assert(nestedJson["items"]["items"]["type"].str == "array");
    assert(nestedJson["items"]["items"]["items"]["type"].str == "string");
    
    // Test enum with single value
    auto singleEnum = SchemaBuilder.enum_("single");
    auto enumJson = singleEnum.toJSON();
    assert(enumJson["type"].str == "string");
    assert(enumJson["enum"].array.length == 1);
    assert(enumJson["enum"].array[0].str == "single");
}
