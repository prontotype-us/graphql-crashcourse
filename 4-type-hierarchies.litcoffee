# 4: Type Hierarchies

Now we've seen custom types, but they  have only used builtin types themselves... not much of a graph yet. In this section we'll compose a hierarchy of custom types to show more nested queries.

    graphql = require 'graphql'
    {inspect} = require './helpers'

## Schema

Once a custom type is defined, it can be used in any other type (including as an Array type, e.g. `Thread.messages`)

    graphql_schema = graphql.buildSchema """

    type Message {
        id: ID
        body: String
        thread: Thread
        sender: User
    }

    type Thread {
        id: ID
        subject: String
        messages: [Message]
    }

    type User {
        id: ID
        username: String
        messages: [Message]
    }

    type Query {
        getMessage(id: ID!): Message
        findMessages(body: String): [Message]
        getThread(id: ID!): Thread
    }

    """

## Resolvers

Each custom type defines its resolver methods, which are just using the getType functions below. These will return objects (or arrays of objects) that represent the custom type from the schema. Remember that the static properties of every object (e.g. `Message.body`) are also considered resolvers, so they can be asked for in a query.

    class Message
        constructor: (id, {body, thread_id, user_id}) ->
            console.log "new Message(id: #{id}, body: '#{body}', thread_id: #{thread_id}, user_id: #{user_id})"
            @id = id
            @body = body
            @thread_id = thread_id
            @user_id = user_id

        thread: ->
            getThread {id: @thread_id}

        sender: ->
            getUser {id: @user_id}

    class Thread
        constructor: (id, {subject}) ->
            console.log "new Thread(id: #{id}, subject: '#{subject}')"
            @id = id
            @subject = subject

        messages: ->
            findMessages {thread_id: @id}

    class User
        constructor: (id, {username}) ->
            console.log "new Thread(id: #{id}, username: '#{username}')"
            @id = id
            @username = username

        messages: ->
            findMessages {user_id: @id}

We'll just use a hard-coded set of items as a fake database,

    messages = {
        0: new Message(0, {body: 'welcome here', thread_id: 0, user_id: 0})
        1: new Message(1, {body: 'hey tahnks for welcom', thread_id: 0, user_id: 1})
    }

    threads = {
        0: new Thread(0, {subject: 'first subject'})
    }

    users = {
        0: new User(0, {username: 'fristpsoter'})
        1: new User(1, {username: '2ndguy'})
    }

And define some generic get/find methods:

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

Then create specific methods and use some as root resolvers:

    getMessage = getType.bind null, messages
    getThread = getType.bind null, threads
    getUser = getType.bind null, users

    findMessages = findType.bind null, messages
    findThreads = findType.bind null, threads
    findUsers = findType.bind null, users

    graphql_root = {
        getMessage
        findMessages
        getThread
    }

## Querying

    runQuery = (query) ->
        graphql.graphql(graphql_schema, query, graphql_root)
            .then ({errors, data}) ->
                console.log "[#{query}]", inspect(errors or data)

As before, when a query method returns a custom type, like `getMessage` &rarr; `Message`, the fields defined on the custom type are then available to descend further. In this case we're fetching the fields `thread: Thread` and `sender: User` from the `Message` type, and getting attributes from those results.

    runQuery """
    {getMessage(id: 0){
        body, thread{subject}, sender{username}
    }}
    """
    # { body: 'welcome here',
    #     thread: { subject: 'first subject' },
    #     sender: { username: 'fristpsoter' } } }

This works the same with arrays. Here we're passing no arguments to `findMessages` to find them all:

    runQuery """
    {findMessages{
        body, thread{subject}, sender{username}
    }}
    """
    # { findMessages:
    #    [ { body: 'welcome here',
    #        thread: { subject: 'first subject' },
    #        sender: { username: 'fristpsoter' } },
    #      { body: 'hey tahnks for welcom',
    #        thread: { subject: 'first subject' },
    #        sender: { username: '2ndguy' } } ] }

And from here, we can get needlessly recursive. It's resolvers all the way down:

    runQuery """
    {getThread(id: 0){
        subject,
        messages{
            body, thread{
                subject, messages{
                    id, sender{
                        username, messages{
                            body
                        }
                    }
                }
            }
        }
    }}
    """
    # { getThread:
    #    { subject: 'first subject',
    #      messages:
    #       [ { body: 'welcome here',
    #           thread:
    #            { subject: 'first subject',
    #              messages:
    #               [ { id: '0',
    #                   sender:
    #                    { username: 'fristpsoter',
    #                      messages: [ { body: 'welcome here' } ] } },
    #                 { id: '1',
    #                   sender:
    #                    { username: '2ndguy',
    #                      messages: [ { body: 'hey tahnks for welcom' } ] } } ] } },
    #         { body: 'hey tahnks for welcom',
    #           thread:
    #            { subject: 'first subject',
    #              messages:
    #               [ { id: '0',
    #                   sender:
    #                    { username: 'fristpsoter',
    #                      messages: [ { body: 'welcome here' } ] } },
    #                 { id: '1',
    #                   sender:
    #                    { username: '2ndguy',
    #                      messages: [ { body: 'hey tahnks for welcom' } ] } } ] } } ] } }

---

Next: [5. Input Types](https://github.com/prontotype-us/graphql-crashcourse/blob/master/5-input-types.litcoffee)
