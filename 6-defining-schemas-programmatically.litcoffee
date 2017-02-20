# 6. Defining Schemas Programmatically

The string-based schema we've been using is a great way to set up simple schemas, and to understand the concepts of GraphQL. However as your schema gets bigger you'll probably want a more programmatic approach - perhaps to build a schema from a JSON file.

    graphql = require 'graphql'
    {inspect} = require './helpers'


## Schema

Remember that a type is a named set of typed fields, which are resolved with some function. When we create the schema programmatically this more obvious, as resolver functions are defined directly on the fields.

For custom types we create a new `GraphQLObjectType` and supply a `name` and `fields`. Every field has a `type` which might be a builtin (`GraphQLString` etc.) or custom type. We can also make list types with the `GraphQLList` wrapper.

Fields using custom types will also need a `resolve` function, which will be in a slightly different shape than before - an extra argument `self` before `args` represents the object that has the fields.

    MessageType = new graphql.GraphQLObjectType
        name: 'Message'
        fields: ->
            id: type: graphql.GraphQLID
            body: type: graphql.GraphQLString
            thread:
                type: ThreadType
                resolve: (self) ->
                    getType threads, {id: self.thread_id}
            sender:
                type: UserType
                resolve: (self) ->
                    getType users, {id: self.user_id}

    ThreadType = new graphql.GraphQLObjectType
        name: 'Thread'
        fields: ->
            id: type: graphql.GraphQLID
            subject: type: graphql.GraphQLString
            messages:
                type: new graphql.GraphQLList MessageType
                resolve: (self) ->
                    findType messages, {thread_id: self.id}

    UserType = new graphql.GraphQLObjectType
        name: 'User'
        fields:
            id: type: graphql.GraphQLID
            username: type: graphql.GraphQLString

When types reference each other you might not have defined the referenced type yet, so GraphQL allows `fields` to be a function which will be executed at runtime.

We define input types with `GraphQLInputObjectType`. This defines the fields we can use for arguments of relevant Mutation queries.

    MessageInputType = new graphql.GraphQLInputObjectType
        name: 'MessageInput'
        fields:
            body: type: graphql.GraphQLString
            thread_id: type: graphql.GraphQLID
            user_id: type: graphql.GraphQLID

As before there's a root Query type, which happens to also be based on the `GraphQLObjectType`. Instead of an object of root resolvers we define the main queries here as fields. Resolve methods will also have an extra argument before `args` called `context`.

    QueryType = new graphql.GraphQLObjectType
        name: 'Query'
        fields:
            getMessage:
                type: MessageType
                args:
                    id: type: graphql.GraphQLID
                resolve: (context, {id}) ->
                    getType(messages, {id})
            getThread:
                type: ThreadType
                args:
                    id: type: graphql.GraphQLID
                resolve: (context, {id}) ->
                    getType(threads, {id})

Similar for the root Mutation type. You have to think carefully about input vs. output types at this point - the `type` of the field itself will always be an output type (what is returned after the mutation), but the `type` of an argument will be an input type. For builtin types it doesn't make a difference, but for custom types you have to supply the correct InputType.

    MutationType = new graphql.GraphQLObjectType
        name: 'Mutation'
        fields:
            createMessage:
                type: MessageType
                args:
                    body: type: graphql.GraphQLString
                    thread_id: type: graphql.GraphQLID
                    user_id: type: graphql.GraphQLID
                resolve: (context, {body, thread_id, user_id}) ->
                    createType(messages, {body, thread_id, user_id})
            createThread:
                type: ThreadType
                args:
                    subject: type: graphql.GraphQLString
                    message:
                        type: MessageInputType
                resolve: (context, {subject, message}) ->
                    new_thread = createType(threads, {subject})
                    if message?
                        message.thread_id = new_thread.id
                        new_message = createType(messages, message)
                    return new_thread

To build the schema we supply the main Query and Mutation types:

    graphql_schema = new graphql.GraphQLSchema
        query: QueryType
        mutation: MutationType

## Resolvers

Because resolvers for each field are defined on the types above, we can do away with the class system from before.

The fake database will now be plain JSON objects:

    messages = {
        0: {id: 0, body: 'welcome here', thread_id: 0, user_id: 0}
        1: {id: 1, body: 'hey tahnks for welcom', thread_id: 0, user_id: 1}
    }

    threads = {
        0: {id: 0, subject: 'first subject'}
    }

    users = {
        0: {id: 0, username: 'fristpsoter'}
        1: {id: 1, username: '2ndguy'}
    }

The generic methods are the same:

    getType = (collection, {id}) ->
        collection[id]

    findType = (collection, query) ->
        found = []
        for item_id, item of collection
            matches = true
            for k, v of query
                if item[k] != v
                    matches = false
            if matches
                found.push item
        return found

    createType = (collection, new_item) ->
        new_item.id = Object.keys(collection).length
        collection[new_item.id] = new_item

We already defined the root queries on the Query type, so no need to attach them to a root context. We can use a blank object instead. This could be used to set configuration or some system state - it will be passed as the first argument to a root query resolver.

    graphql_root = {}

## Querying

We don't have to change anything about our queries with the new schema.

    runQuery = (query) ->
        graphql.graphql(graphql_schema, query, graphql_root)
            .then ({errors, data}) ->
                console.log "[#{query}]", inspect(errors or data)

    runQuery """
    {getMessage(id: 0){
        body, thread{subject}, sender{username}
    }}
    """
    # { body: 'welcome here',
    #     thread: { subject: 'first subject' },
    #     sender: { username: 'fristpsoter' } } }

    runQuery """
    {getThread(id: 0){
        subject, messages{
            body, sender{username}
        }
    }}
    """
    # { getThread:
    #    { subject: 'first subject',
    #      messages:
    #       [ { body: 'welcome here', sender: { username: 'fristpsoter' } },
    #         { body: 'hey tahnks for welcom',
    #           sender: { username: '2ndguy' } } ] } }

    runQuery """
    mutation{createMessage(thread_id: 0, user_id: 0, body: "ur welcome lol"){
        body, thread{subject}, sender{username}
    }}
    """
    # { createMessage:
    #    { body: 'ur welcome lol',
    #      thread: { subject: 'first subject' },
    #      sender: { username: 'fristpsoter' } } }

    runQuery """
    mutation{createThread(subject: "just a thread here", message: {body: "just a mesg here", user_id: 0}){
        subject
        messages{body, sender{username}}
    }}
    """
    # { createThread:
    #   { subject: 'just a thread here',
    #     messages:
    #      [ { body: 'just a mesg here',
    #          sender: { username: 'fristpsoter' } } ] } }

