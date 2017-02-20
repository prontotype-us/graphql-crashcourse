# 2. Query Arguments

GraphQL lets you pass arguments to queries to be more specific. Arguments are passed alongside the field name in the format `key: value`, e.g. `{threads(status: "archived")}`.

    graphql = require 'graphql'
    {inspect} = require './helpers'

## Schema

Arguments are defined like a field, with a name and type. Arguments may be required (they're optional by default) by adding `!` to the end, and you can set a default value with `= value`.

Also note the array type, which can be used with any other type.

    graphql_schema = graphql.buildSchema """

    type Query {
        randomNumber(max: Int = 1): Float
        randomNumbers(n: Int!, max: Int = 1): [Float]
        doubleNumbers(ns: [Int]!): [Int]
    }

    """

## Resolver functions

When a resolver functions has arguments, they will be passed in as a single object.

    randomNumber = ({max}) ->
        Math.random() * max

    randomNumbers = ({n, max}) ->
        [0...n].map -> randomNumber {max}

    doubleNumbers = ({ns}) ->
        ns.map (n) -> n * 2

Then we can add these to the root resolver:

    graphql_root = {
        randomNumber
        randomNumbers
        doubleNumbers
    }

## Querying

The query running function is the same as before:

    runQuery = (query) ->
        graphql.graphql(graphql_schema, query, graphql_root)
            .then ({errors, data}) ->
                console.log "[#{query}]", inspect(errors or data)

Arguments, if supplied, are comma separated in parentheses next to the resolver name:

    runQuery "{randomNumber}"
    # { randomNumber: 97.11593144363752 }

    runQuery "{randomNumber(max: 100)}"
    # { randomNumber: 97.11593144363752 }

    runQuery "{randomNumbers(n: 3, max: 10)}"
    # { randomNumbers: [ 0.8330031743331603, 0.48865807694022223, 0.9570725789206593 ]}

Any valid JSON type can be passed as an argument value:

    runQuery "{doubleNumbers(ns: [1, 2, 3])}"
    # { doubleNumbers: [ 2, 4, 6 ] }

---

Next: [3. Custom Types](https://github.com/prontotype-us/graphql-crashcourse/blob/master/3-custom-types.litcoffee)
