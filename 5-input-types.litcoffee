# 4: Input types

So far we have retrieved data, but haven't had any input of our own. GraphQL separates the concerns of input from output with *input types* and *mutation queries*. For the most part, these are slight modifications of the regular types and queries.

    graphql = require 'graphql'
    {inspect} = require './helpers'

## Schema

Input types are like regular types, with a different prefix. The point is to define a set of fields that can be changed (or created) from user input, separate from the potentially different fields used when querying. An example is setting an ID field instead of fetching the relevant sub-object.

Here we use the same `Message` model as before, and create a `MessageInput` input type to complement it. We'll leave out the `id` field since that shouldn't be changed, and instead of the `thread` object type for output, we have a `thread_id` ID type on the input.

For ease of reference we'll also add a "Input" prefix to the input version of each type, but you don't have to &mdash; Mutation queries can only take Input types as arguments, so the correct type is implied if they share names.

    graphql_schema = graphql.buildSchema """

    # Regular types

    type Message {
        id: ID
        body: String
        thread: Thread
    }

    type Thread {
        id: ID
        subject: String
    }

    # Input types

    input MessageInput {
        body: String
        thread_id: ID
    }

    input ThreadInput {
        subject: String
    }

    # Regular queries

    type Query {
        getMessage(id: ID!): Message
    }

    # Mutation queries

    type Mutation {
        createMessage(input: MessageInput): Message
        updateMessage(id: ID!, input: MessageInput): Message
    }

    """

## Resolvers

We'll define a class for our custom type, and a `getMessage` for the root Query type. Note that we don't have to define a `MessageInput` type, that will be a regular JSON object supplied by the query.

    class Message
        constructor: (id, {body, thread_id}) ->
            console.log "new Message(id: #{id}, body: '#{body}', thread_id: '#{thread_id}')"
            @id = id
            @body = body
            @thread_id = thread_id

        update: (update) ->
            Object.assign @, update

        thread: ->
            getThread {id: @thread_id}

    class Thread
        constructor: (id, {subject}) ->
            console.log "new Thread(id: #{id}, subject: '#{subject}')"
            @id = id
            @subject = subject

        update: (update) ->
            Object.assign @, update

    messages = {
        0: new Message(0, {body: 'welcome here', thread_id: 0})
    }

    threads = {
        0: new Thread(0, {subject: 'first subject'})
    }

    getMessage = ({id}) ->
        return messages[id]

    getThread = ({id}) ->
        return threads[id]

The mutation methods are also just regular functions, the only difference is that these will have the input argument as an object, with the fields defined in the MessageInput type above.

    createMessage = ({input}) ->
        id = Object.keys(messages).length
        new Message(id, input)

    updateMessage = ({id, input}) ->
        getMessage({id}).update(input)

Methods for both the root Query and Mutation are attached to the root resolver object:

    graphql_root = {
        getMessage
        createMessage
        updateMessage
    }

## Querying

    runQuery = (query) ->
        graphql.graphql(graphql_schema, query, graphql_root)
            .then ({errors, data}) ->
                console.log "[#{query}]", inspect(errors or data)

Unlike regular queries, mutations are specified with `mutation` at the beginning. These examples also both use the `MessageInput` type as an argument, the value of which is a regular JSON object. Otherwise mutation queries behave the same, returning the type you specify, so you can descend further in the graph from there.

    runQuery """{getMessage(id: 0){body, thread{subject}}}"""
    # { getMessage: { body: 'welcome here', thread: { subject: 'first subject' } } }

Mutation queries return types, so you can perform regular sub-queries from there:

    runQuery """mutation{updateMessage(id: 0, input: {body: "rewrote body"}){body}}"""
    # { updateMessage: { body: 'rewrote body' } }

    runQuery """mutation{createMessage(input: {body: "a test", thread_id: 0}){body, thread{subject}}}"""
    # { createMessage: { body: 'a test', thread: { subject: 'first subject' } } }
