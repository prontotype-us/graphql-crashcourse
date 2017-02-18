# # 5. Easier schemas with graphql-tools

# We can see the limitations of using pure GraphQL schema already, notably defining all the methods for connections between types. This time we'll try a helper library [graphql-tools](https://github.com/apollographql/graphql-tools) which does some extra work with the schema to parse

graphql = require 'graphql'
graphql_tools = require 'graphql-tools'
{randomChoice, inspector} = require './helpers'

raw_schema = """
type Thread {
    id: ID
    subject: String
}

type Message {
    id: ID
    body: String
    thread: Thread
    things(find: ThingInput): [Thing]
}

type Thing {
    id: ID
    message: Message
    name: String
}

input ThingInput {
    message_id: ID
    name: String
}

input MessageInput {
    thread_id: ID
    body: String
}

type Query {
    message(id: ID!): Message
    messages(find: MessageInput): [Message]
}

type Mutation {
    createMessage(input: MessageInput): Message
    updateMessage(id: ID!, input: MessageInput): Message
}
"""

# Here is a simple data model with some get / find methods:

messages = {
    0: {id: 0, thread_id: 0, body: 'welcome here'}
}

threads = {
    0: {id: 0, subject: 'first thread yo'}
    1: {id: 1, subject: 'second thread yo'}
}

things = {
    3: {id: 3, name: "One thing", message_id: 0}
    4: {id: 4, name: "Some thing", message_id: 0}
    5: {id: 5, name: "Another thing", message_id: 1}
}

getMessage = (id) ->
    messages[id]

getThread = (id) ->
    threads[id]

getThing = (id) ->
    things[id]

findMessages = (query) ->
    filterByQuery query, messages

findThreads = (query) ->
    filterByQuery query, threads

findThings = (query) ->
    filterByQuery query, things

# And here's a helper function to filter these lists

filterByQuery = (query, items) ->
    console.log 'filterByQuery', query
    found_items = []
    for item_id, item of items
        should_add = true
        for k, v of query
            if item[k] != v
                should_add = false
                continue
        if should_add
            found_items.push item
    return found_items

# The extra piece that graphql-tool uses is the "Resolver Map", defining a resolver function for each field of each type in the schema.

resolver_map =
    Message: {
        thread: (self, args) ->
            return getThread(self.id)
        things: (self, args) ->
            query = Object.assign {message_id: self.id}, (args.find or {})
            return findThings(query)
    }
    Thing: {
        message: (self, args) ->
            return getMessage(self.message_id)
    }

graphql_schema = graphql_tools.makeExecutableSchema
    typeDefs: raw_schema
    resolvers: resolver_map

# We still have to define the root query methods: 

graphql_root =
    getMessage: ({id}) ->
        getMessage id

    messages: ({find}) ->
        findMessages find

    createMessage: ({input}) ->
        id = Object.keys(messages).length
        message = Object.assign input, {id}
        messages[id] = message
        return message

    updateMessage: ({id, input}) ->
        Object.assign messages[id], input

runQuery = (query) ->
    graphql.graphql(graphql_schema, query, graphql_root)
        .then ({errors ,data}) ->
            errors or data

# And now we can query our models, sub-models, and even pass additional arguments to sub-queries. Notice the "find" argument which made it possible in the schema to refer to the relevant input type, instead of re-defining the query arguments.

runQuery """
{
    messages(find: {body:"welcome here"}){
        body,
        thread{subject},
        things(find: {name: "One thing"}){name, message{body}}
    }
}
"""
    .then inspector 'get message'

runQuery """
mutation{
    createMessage(input: {body:"test two"}){
        thread{subject}, body, things{name}
    }
}
"""
    .then inspector 'create message'

