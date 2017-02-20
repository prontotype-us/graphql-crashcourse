# 6. Somata Schema Interlude

To demonstrate that GraphQL does not have to be about fetching data from a database, this interlude builds a schema out of Somata service calls.

    graphql = require 'graphql'
    somata = require 'somata'
    {inspect} = require './helpers'

## Schema

    graphql_schema = graphql.buildSchema """

    type User {
        email: String
        name: String
        wallets: [Wallet]
        journals: [Journal]
    }

    type Wallet {
        asset: String
        balance: Float
        value: Float
    }

    type Journal {
        topic: String
        entries: [Entry]
    }

    type Entry {
        body: String
        n_words: Int
    }

    type Query {
        getUser(email: String!): User
    }

    type Mutation {
        createEntry(topic: String, body: String!): Entry
    }

    """

## Resolvers

We'll define a few services inline just as a proof of concept. Each of these services supplies a piece of the schema above.

    new somata.Service 'example:users', {
        getUser: (email, cb) ->
            cb null, {email}
    }

    new somata.Service 'example:wallets', {
        findWallets: (email, cb) ->
            cb null, [
                {asset: "btc", balance: 2}
                {asset: "pesos", balance: 53}
            ]
    }

    new somata.Service 'example:market', {
        getExchangeRate: (asset, cb) ->
            rate = switch asset
                when "btc"
                    1010
                when "pesos"
                    0.5
            cb null, rate
    }

    journals =
        'gigstar@gmail.com': [
            {topic: 'food'}
            {topic: 'books'}
        ]

    entries =
        food: [
            {body: "i ate a sandwich"}
            {body: "i had some cheese"}
        ]
        books: [
            {body: "i read a book called book"}
        ]

    new somata.Service 'example:journals', {
        findJournals: (email, cb) ->
            cb null, journals[email]
        findEntries: (topic, cb) ->
            cb null, entries[topic]
        createEntry: (topic, body, cb) ->
            new_entry = {body}
            entries[topic].push new_entry
            cb null, new_entry
    }

    new somata.Service 'example:counter', {
        countWords: (s, cb) ->
            cb null, s.split(' ').length
    }

A helper function to turn a Somata call into a promise:

    client = new somata.Client

    remotePromise = (service, method, args...) ->
        new Promise (resolve, reject) ->
            client.remote service, method, args..., (err, user) ->
                if user?
                    resolve user
                else
                    reject err

The types will be defined with resolvers that call `remotePromise` to get values:

    class User
        constructor: ({email}) ->
            @email = email

        wallets: ->
            remotePromise 'example:wallets', 'findWallets', @email
                .then (wallets) -> wallets.map (w) -> new Wallet w

        journals: ->
            remotePromise 'example:journals', 'findJournals', @email
                .then (journals) -> journals.map (j) -> new Journal j

    class Wallet
        constructor: ({asset, balance}) ->
            @asset = asset
            @balance = balance

        value: ->
            remotePromise 'example:market', 'getExchangeRate', @asset
                .then (exchange_rate) => exchange_rate * @balance

    class Journal
        constructor: ({topic}) ->
            @topic = topic

        entries: ->
            remotePromise 'example:journals', 'findEntries', @topic
                .then (entries) -> entries.map (e) -> new Entry e

    class Entry
        constructor: ({timestamp, body}) ->
            @timestamp = timestamp
            @body = body

        n_words: ->
            remotePromise 'example:counter', 'countWords', @body

And the root `getUser` method to make queries:

    graphql_root = {
        getUser: ({email}) ->
            remotePromise 'example:users', 'getUser', email
                .then (user) -> new User user
        createEntry: ({topic, body}) ->
            remotePromise 'example:journals', 'createEntry', topic, body
                .then (entry) -> new Entry entry
    }

## Querying

    runQuery = (query) ->
        graphql.graphql(graphql_schema, query, graphql_root)
            .then ({errors, data}) ->
                console.log "[#{query}]", inspect(errors or data)

This is inside a timeout to let the inline services register first:

    setTimeout ->

        runQuery """{
            getUser(email: "gigstar@gmail.com"){
                email,
                wallets{asset, balance, value}
                journals{topic, entries{body, n_words}}
            }
        }
        """
        # { getUser:
        #    { email: 'gigstar@gmail.com',
        #      wallets:
        #       [ { asset: 'btc', balance: 2, value: 2020 },
        #         { asset: 'pesos', balance: 53, value: 26.5 } ],
        #      journals:
        #       [ { topic: 'food',
        #           entries:
        #            [ { body: 'i ate a sandwich', n_words: 4 },
        #              { body: 'i had some cheese', n_words: 4 } ] },
        #         { topic: 'books',
        #           entries: [ { body: 'i read a book called book', n_words: 6 } ] } ] } }

        runQuery """mutation{
            createEntry(topic: "food", body: "i am probably eating a bagel right now"){
                body, n_words
            }
        }
        """
        # { createEntry: { body: 'i am probably eating a bagel right now', n_words: 8 } }

    , 500

---

Next: [7. Defining Schemas Programmatically](https://github.com/prontotype-us/graphql-crashcourse/blob/master/7-defining-schemas-programmatically.litcoffee)
