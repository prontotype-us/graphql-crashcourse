# 1. Simple Schemas & Queries

GraphQL is a language that makes it easy to query arbitrarily nested data, getting (and executing) only the results you need. The two most important pieces of GraphQL are the *schema*, which defines the possible values and relationships of your data, and *queries*, which specify the exact shape of the data you want to retrieve.

    graphql = require 'graphql'
    {randomChoice, inspect} = require './helpers'

## The schema

The GraphQL schema defines *types* and their *fields*, which also are typed. There are a number of built in types like String, ID and Int. You may also use custom types for fields to define a hierarchy (as you'll see in [part 4](https://github.com/prontotype-us/graphql-crashcourse/blob/master/4-type-hierarchies.litcoffee))

At the root of the schema is a "Query" object, which defines the possible queries you can make. Each field here represents the name of a possible query and the type it should return.

    graphql_schema = graphql.buildSchema """

    type Query {
        randomGreeting: String
        randomNumber: Float
        somethingAsync: Int
        somethingStatic: Int
    }

    """

## Resolver functions

When a query is executed, it tries to "resolve" the fields that you ask for, returning some data of the correct type. In this example, if you queried for `{randomGreeting}` it would try to resolve as a string and output something like `{randomGreeting: 'hi there'}`.

Each of these so-called "resolvers" is just a function that returns either a value or a promise. It can even be a static value.

    randomGreeting = ->
        randomChoice ['hi there', 'welcome', 'how do you do']

    randomNumber = -> Math.random()

    somethingAsync = ->
        new Promise (resolve, reject) ->
            setTimeout ->
                resolve 5
            , 200

    somethingStatic = 10

The root resolver object defines the methods that the root Query object (and the root Mutation object later) will use.

    graphql_root = {
        randomGreeting
        randomNumber
        somethingAsync
        somethingStatic
    }

## Querying

We'll define a helper function to run a query with our schema and print the results. The arguments to the main `graphql` function are the schema, query string, and root resolver object from above.

    runQuery = (query) ->
        graphql.graphql(graphql_schema, query, graphql_root)
            .then ({errors, data}) ->
                console.log "[#{query}]", inspect(errors or data)

Now we can make some queries. The most basic query gets a field from the root Query object and runs the resolver. In this case, we will be calling `randomGreeting` which should return a random string:

    runQuery "{randomGreeting}"

*Output:* `{ randomGreeting: 'how do you do' }`

Even the most basic query is wrapped in brackets. You can think of the query as a value-less JSON object that will be filled in by the resolvers.

We can add more keys to the query to get multiple results at once:

    runQuery "{randomGreeting, randomNumber}"

*Output:* `{ randomGreeting: 'welcome', randomNumber: 0.9443729041640672 }`

    runQuery "{somethingAsync, somethingStatic, randomNumber}"

*Output:* `{ somethingAsync: 5, somethingStatic: 10, randomNumber: 0.5087247788432705 }`

---

Next: [2. Query Arguments](https://github.com/prontotype-us/graphql-crashcourse/blob/master/2-query-arguments.litcoffee)
