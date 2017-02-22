# 8. Parsed Object Based Schema

    graphql = require 'graphql'
    {inspect} = require './helpers'

To satisfy most Prontotype project schemas we just define an object's field types and attachments based on IDs. In order to make this easy we'll invent a simplified schema format.

It would be possible to parse the true GraphQL schema with given parsing tools, but I'm not going into that. The main purpose of this is to demonstrate building a schema programmatically from another format (imagine it was from a JSON object instead).

In this schema each type defines its singular and plural name, then each field as either two pieces (a name and built in type) or four pieces (a name, referencing collection, reference "direction", and ID key). The direction `>` will mean that *this* object has an ID of the given key, which will be used to search for an external object, e.g. `interaction.user_id > user`. The direction `<` will mean that the external object has an ID, e.g `user < interactions.user_id`.

    object_schema = """
    User
        name String
        email String
        interactions Interaction < user_id

    Interaction
        user User > user_id
        assessment Assessment > assessment_id
        responses Response < interaction_id

    Assessment
        name String
        items Item < assessment_id
        interactions Interaction < assessment_id

    Item
        body String
        answers Answer < item_id

    Answer
        body String

    Response
        interaction Interaction > interaction_id
        item Item > item_id
        answer Answer > answer_id

    Company companies
        name String
        users User < company_id
    """

## Parsing the Schema

To tokenize this format, we first split into "sections" separated by two blank lines, then split each line by spaces:

    tokenizeSchema = (object_schema) ->
        object_schema.split('\n\n').map tokenizeSection

    tokenizeSection = (section) ->
        section = section.split('\n')
        key = section.shift()
        lines = section.map (line) ->
            line.trim().split(' ')
        [key, lines]

To parse from those tokens, we take the first line of each section as the type name, and the other lines are interpreted based on the number of tokens:

    parseSection = ([key, lines]) ->
        [name, collection] = key.split(' ')
        singular = name.toLowerCase()
        if !collection?
            collection = singular + 's'
        {
            name, singular, collection
            fields: lines.map parseLine
        }

    parseLine = (line) ->
        if line.length == 2
            [name, type] = line
            {name, type}
        else
            [name, type, ref_type, key] = line
            if ref_type == '>'
                method = 'get'
            else
                method = 'find'
            {name, method, type, key}

    tokenized = tokenizeSchema object_schema
    parsed = tokenized.map parseSection

Now we should have a parsed JSON object from the above string schema. This would be a good starting point for a real schema based on a JSON file.

    console.log inspect parsed
    # [ { name: 'User',
    #     collection: 'users',
    #     fields:
    #      [ { name: 'name', type: 'string' },
    #        { name: 'email', type: 'string' },
    #        { name: 'interactions',
    #          method: 'find',
    #          type: 'Interaction',
    #          key: 'user_id' } ] },
    #   { name: 'Interaction',
    #     collection: 'interactions',
    #     fields:
    #      [ { name: 'user', method: 'get', type: 'User', key: 'user_id' },
    #        { name: 'assessment',
    #          method: 'get',
    #          type: 'Assessment',
    #          key: 'assessment_id' } ] },
    # ...

## Building the Schema

We'll keep a map of builtin types and custom types.

    builtin_types =
        String: graphql.GraphQLString

    custom_types = {}

To build the schema we'll be iterating over the parsed types and their fields to construct our custom `GraphQLObjectType`s.

    parsed.map (parsed_type) ->
        custom_types[parsed_type.name] = new graphql.GraphQLObjectType
            name: parsed_type.name
            singular: parsed_type.singular
            collection: parsed_type.collection
            fields: ->
                fieldsForParsedFields parsed_type.fields

To create the output fields for a custom type we iterate over the parsed fields:

    fieldsForParsedFields = (parsed_fields) ->
        fields = {id: type: graphql.GraphQLID} # Everything has an ID by default

        parsed_fields.map (parsed_field) ->

            # Reference to a builtin type
            if builtin_type = builtin_types[parsed_field.type]
                fields[parsed_field.name] = type: builtin_type

            else
                # Add a regular ID field for get attachments, e.g. interaction.user_id
                if parsed_field.method == 'get'
                    fields[parsed_field.key] = type: graphql.GraphQLID

                # Create the full type and resolver
                fields[parsed_field.name] = customFieldForParsedField parsed_field

        return fields

For a custom field, we return the custom type as `type` and a `resolve` function. Depending on the attachment method (get `>` vs. find `<`) we use either the `getType` or `findType` methods, building the appropriate query from the current object.

    customFieldForParsedField = (parsed_field) ->
        Type = custom_types[parsed_field.type]
        {collection} = Type._typeConfig

        # Get attachments (>) look for an external object by id from self[key]
        if parsed_field.method == 'get'
            resolve = (self, args) ->
                query = {id: self[parsed_field.key]}
                return getType collection, query

        # Find attachments (<) look for other objects matching obj[key] = self.id
        else if parsed_field.method == 'find'
            Type = new graphql.GraphQLList Type # Will return a list
            resolve = (self, args) ->
                query = {}
                query[parsed_field.key] = self.id
                return findType collection, query

        return {
            type: Type
            resolve
        }

We have to make a main query object still. Its fields are resolvers as usual, this time we'll iterate through all the types to make a root get and find method for each, based on its values for `singular` and `collection`.

    query_fields = {}

    parsed.map (parsed_type) ->
        query_fields[parsed_type.singular] =
            type: custom_types[parsed_type.name]
            args:
                id: type: graphql.GraphQLID
            resolve: (context, query) ->
                getType(parsed_type.collection, query)

        query_fields[parsed_type.collection] =
            type: new graphql.GraphQLList custom_types[parsed_type.name]
            args:
                id: type: graphql.GraphQLID
            resolve: (context, query) ->
                findType(parsed_type.collection, query)

    QueryType = new graphql.GraphQLObjectType
        name: 'Query'
        fields: query_fields

*TODO: Mutations*

    graphql_schema = new graphql.GraphQLSchema
        query: QueryType
        # mutation: MutationType

## Resolvers

The resolvers will again be based on a static database, but you can imagine replacing these with data queries. To make that easier to realize the `collection` parameter passed to the `getType` and `findType` methods is now a string referring to the collection name.

    db = {
        users: {
            0: {id: 0, email: "test@prontotype.us"}
        }
        interactions: {
            0: {id: 0, user_id: 0, assessment_id: 0}
            1: {id: 1, user_id: 0, assessment_id: 2}
            2: {id: 2, user_id: 1, assessment_id: 0}
            3: {id: 3, user_id: 1, assessment_id: 1}
        }
        assessments: {
            0: {id: 0, name: "Dog Test"}
            1: {id: 1, name: "Dark Side"}
            2: {id: 2, name: "Values"}
        }
        items: {
            0: {id: 0, assessment_id: 0, body: "Are you a dog?"}
            1: {id: 1, assessment_id: 0, body: "Are you not a dog?"}
        }
        answers: {
            0: {id: 0, item_id: 0, body: "Yes", scale: "Dog", value: 1}
            1: {id: 1, item_id: 0, body: "No", scale: "Dog", value: 0}
            2: {id: 2, item_id: 1, body: "Yes", scale: "Dog", value: 0}
            3: {id: 3, item_id: 1, body: "No", scale: "Dog", value: 1}
        }
        responses: {
            0: {id: 0, interaction_id: 0, item_id: 0, answer_id: 0}
        }
    }

    getType = (collection, {id}) ->
        console.log '[getType]', collection, arguments[1]
        db[collection][id]

    findType = (collection, query) ->
        console.log '[findType]', collection, arguments[1]
        found = []
        for item_id, item of db[collection]
            matches = true
            for k, v of query
                if item[k] != v
                    matches = false
            if matches
                found.push item
        return found

    graphql_root = {}

## Querying

    runQuery = (query) ->
        graphql.graphql(graphql_schema, query, graphql_root)
            .then ({errors, data}) ->
                console.log "[#{query}]", inspect(errors or data)

    runQuery """
    {user(id: 0){
        email, interactions{
            assessment{
                name
            }
            responses{
                item{body},
                answer{body}
            }
        }
    }}
    """
    # { user:
    #    { email: 'test@prontotype.us',
    #      interactions:
    #       [ { assessment:
    #            { name: 'Dog Test',
    #              items:
    #               [ { body: 'Are you a dog?',
    #                   answers: [ { body: 'Yes' }, { body: 'No' } ] },
    #                 { body: 'Are you not a dog?', answers: [] } ] } },
    #         { assessment: { name: 'Values', items: [] } } ] } }

    runQuery """{
        assessments{
            id, name
            interactions{
                id, assessment_id
            }
        }
    }"""
    # { assessments:
    #    [ { id: '0',
    #        name: 'Dog Test',
    #        interactions:
    #         [ { id: '0', assessment_id: '0' },
    #           { id: '2', assessment_id: '0' } ] },
    #      { id: '1',
    #        name: 'Dark Side',
    #        interactions: [ { id: '3', assessment_id: '1' } ] },
    #      { id: '2',
    #        name: 'Values',
    #        interactions: [ { id: '1', assessment_id: '2' } ] } ] }

