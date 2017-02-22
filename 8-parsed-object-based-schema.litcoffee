# 8. Parsed Object Based Schema

    graphql = require 'graphql'
    {inspect} = require './helpers'

To satisfy most Prontotype project schemas we just define an object's field types and attachments based on well-named IDs. In order to make this easy we'll invent a simplified schema format.

It would be possible to parse the true GraphQL schema with existing parsing tools, but I'm not going into that. The main purpose of this is to demonstrate building a schema programmatically from another format (imagine it was from a JSON object instead).

In this schema each type defines its singular and plural name, then each field as either two pieces (a name and built in type) or four pieces (a name, referenced type, reference "direction", and ID key).

For reference directions, we use the two common attachment strategies:

* `>` will mean that *this* object has key that represents an external object's ID,
	* for example `User.company > company_id` &rarr;  `user.company = companies(id = user.company_id)`
* `<` will mean that some external object(s) have a key that matches this object's ID,
	* for example `User.interactions < user_id` &rarr; `user.interactions = interactions(user_id = user.id)`

    object_schema = """
    User
        name String
        email String
        interactions Interaction < user_id

    Interaction
        status String
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

## Parsing the String Schema

To tokenize this format, we first split into "sections" separated by one blank lines (two newlines), then trim indentation and split each line by spaces:

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

## Building the GraphQL Schema

We'll keep a map of builtin types and custom types.

    parsed_types = {} # For easy reference to original parsed types
    parsed.map (parsed_type) ->
        parsed_types[parsed_type.name] = parsed_type

    builtin_types =
        String: graphql.GraphQLString

    custom_types = {}
    input_types = {}

To build the schema we'll be iterating over the parsed types and their fields to construct our custom `GraphQLObjectType`s.

    parsed.map (parsed_type) ->
        custom_types[parsed_type.name] = new graphql.GraphQLObjectType
            name: parsed_type.name
            fields: ->
                fieldsForParsedFields parsed_type.fields

Similar for input types, appending "Input" to the name and creating a `GraphQLInputObjectType`:

    parsed.map (parsed_type) ->
        input_types[parsed_type.name + 'Input'] = new graphql.GraphQLInputObjectType
            name: parsed_type.name + 'Input'
            fields: ->
                inputFieldsForParsedFields parsed_type.fields

To create the output fields for a custom type we iterate over the parsed fields and add the definition for either a builtin type or a custom type:

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

For a custom field, we need the `type` and a `resolve` function. Depending on the attachment method (get `>` vs. find `<`), the resolve function will use the `getType` or `findType` methods and build the query from the current object.

To enable filtering at the field level, e.g. `{user{interactions(query: {status: "done"}){...}}}`, we add a single argument `query`, which will be the input type corresponding to this type. *Note:* The reasoning for doing it this way (instead of direct arguments like `interactions(status: "done")` is firstly that it allows us to reuse the input type, secondly that this allows us to later pass non-query arguments for sorting and pagination.

    customFieldForParsedField = (parsed_field) ->
        {collection} = parsed_types[parsed_field.type]
        Type = custom_types[parsed_field.type]
        InputType = input_types[parsed_field.type + 'Input']

        # Get attachments (>) look for an external object by id from self[key]
        if parsed_field.method == 'get'
            resolve = (self, args) ->
                query = {id: self[parsed_field.key]}
                if args.query?
                    Object.assign query, args.query
                return getType collection, query

        # Find attachments (<) look for other objects matching obj[key] = self.id
        else if parsed_field.method == 'find'
            Type = new graphql.GraphQLList Type # Will return a list
            resolve = (self, args) ->
                query = {}
                query[parsed_field.key] = self.id
                if args.query?
                    Object.assign query, args.query
                return findType collection, query

        return {
            type: Type
            args:
                query: type: InputType
            resolve
        }

To create the fields for input types we use the same strategy, but it will be much simpler because all of the input-able fields are builtins.

    inputFieldsForParsedFields = (parsed_fields) ->
        fields = {}
        parsed_fields.map (parsed_field) ->
            if builtin_type = builtin_types[parsed_field.type]
                fields[parsed_field.name] = type: builtin_type
            else if parsed_field.method == 'get'
                fields[parsed_field.key] = type: graphql.GraphQLID
        return fields

Lastly we have to build the main Query and Mutation objects. Their fields are resolvers as usual.

The shape for each of the main query and mutation methods is:

* `get(id: _)`
* `find(query: {...})`
* `create(query: {...})`
* `update(id: _, query: {...})`

    query_fields = {}
    mutation_fields = {}

    parsed.map (parsed_type) ->
        {singular, collection} = parsed_type
        Type = custom_types[parsed_type.name]
        InputType = input_types[parsed_type.name + 'Input']

        query_fields[singular] =
            type: Type
            args:
                id: type: graphql.GraphQLID
            resolve: (context, {id}) ->
                getType(collection, {id})

        query_fields[collection] =
            type: new graphql.GraphQLList Type
            args:
                query: type: InputType
            resolve: (context, {query}) ->
                findType(collection, query)

        mutation_fields['create_' + singular] =
            type: Type
            args:
                create: type: InputType
            resolve: (context, {id, create}) ->
                createType(collection, create)

        mutation_fields['update_' + singular] =
            type: Type
            args:
                id: type: graphql.GraphQLID
                update: type: InputType
            resolve: (context, {id, update}) ->
                updateType(collection, id, update)

    QueryType = new graphql.GraphQLObjectType
        name: 'Query'
        fields: query_fields

    MutationType = new graphql.GraphQLObjectType
        name: 'Mutation'
        fields: mutation_fields

    graphql_schema = new graphql.GraphQLSchema
        query: QueryType
        mutation: MutationType

## Resolvers

The resolvers will again be based on a static database, but you can imagine replacing these with data queries. To make that easier to realize the `collection` parameter passed to the `getType` and `findType` methods is now a string referring to the collection name.

    db = {
        users: {
            0: {id: 0, email: "test@prontotype.us"}
            1: {id: 1, email: "jones@test.nest"}
        }
        interactions: {
            0: {id: 0, user_id: 1, assessment_id: 0}
            1: {id: 1, user_id: 0, assessment_id: 2}
            2: {id: 2, user_id: 0, assessment_id: 0, status: "done"}
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
            0: {id: 0, interaction_id: 2, item_id: 0, answer_id: 0}
            1: {id: 1, interaction_id: 2, item_id: 1, answer_id: 1}
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

    createType = (collection, new_item) ->
        console.log '[createType]', collection, new_item
        new_id = Object.keys(db[collection]).length
        new_item.id = new_id
        db[collection][new_id] = new_item

    updateType = (collection, id, update) ->
        item = getType collection, {id}
        Object.assign item, update

    graphql_root = {}

## Querying

    runQuery = (query) ->
        graphql.graphql(graphql_schema, query, graphql_root)
            .then ({errors, data}) ->
                console.log "[#{query}]", inspect(errors or data)

    runQuery """
    {user(id: 0){
        email,
        interactions(query: {status: "done"}){
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
    #       [ { assessment: { name: 'Dog Test' },
    #           responses:
    #            [ { item: { body: 'Are you a dog?' }, answer: { body: 'Yes' } },
    #              { item: { body: 'Are you not a dog?' }, answer: { body: 'No' } } ] } ] } }

    runQuery """mutation{
        update_user(
            id: 0,
            update: {
                email: "testr@net.net"
            }
        ){id, email}
    }
    """
    # { update_user: { id: '0', email: 'testr@net.net' } }

    runQuery """mutation{
        create_response(create: {interaction_id: 1, item_id: 0, answer_id: 0}){
            id, item{body}, answer{body}
        }
    }
    """
    # { create_response:
    #    { id: '2',
    #      item: { body: 'Are you a dog?' },
    #      answer: { body: 'Yes' } } }

