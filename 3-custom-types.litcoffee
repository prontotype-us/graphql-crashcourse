# 3. Custom Types

We've seen a few built in types, but the real point of GraphQL is to define the graph of your own type system to make it queriable. This is acheived with custom types, which also have their own fields (and resolver methods).

    graphql = require 'graphql'
    {inspect} = require './helpers'

## Schema

A custom type is defined just like the Query type we have been using - as a named set of typed fields, which represent resolver functions that should return something of the correct type.

Here a `RandomDie` type is defined with a few fields. Like the Query object, these fields represent resolver functions that resolve to some type.

Note that we'll still need a root Query type as an "entry point" for making queries. `getDie(n_sides)` will return an instance of our `RandomDie` type with the given number of sides.

    graphql_schema = graphql.buildSchema """

    type RandomDie {
        n_sides: Int
        roll: Int
        rolls(n_rolls: Int!): [Int]
    }

    type Query {
        getDie(n_sides: Int!): RandomDie
    }

    """

## Resolvers

When a custom type is resolved, it will just be a regular Javascript object (in fact, custom types inherit from a base Object type by default). In this example we'll define a class to encapsulate a `RandomDie` object and its sub-fields.

    class RandomDie
        constructor: ({n_sides}) ->
            console.log "new RandomDie(n_sides: #{n_sides})"
            @n_sides = n_sides

        roll: ->
            Math.ceil Math.random() * @n_sides

        rolls: ({n_rolls}) ->
            [0...n_rolls].map => @roll()

The `getDie` method will pass the arguments it gets to the `RandomDie` constructor, and return a new instance:

    getDie = ({n_sides}) ->
        return new RandomDie({n_sides})

    graphql_root = {
        getDie
    }

## Querying

    runQuery = (query) ->
        graphql.graphql(graphql_schema, query, graphql_root)
            .then ({errors, data}) ->
                console.log "[#{query}]", inspect(errors or data)

When a query asks for an object type, it must also specify which of the object's fields to return. It would not work to make a query like `{getDie(n_sides: 6)}` by itself (you might hope it returns the whole object, but remember you are templating the response with the query).

Just like the root resolvers, the resolvers attached to an object can be functions that return some value (or a promise):

    runQuery "{getDie(n_sides: 3){roll}}"
    # { getDie: { roll: 2 } }

Or they can be static values:

    runQuery "{getDie(n_sides: 3){n_sides}}"
    # { getDie: { n_sides: 3 }}

And sub-resolvers may also have arguments:

    runQuery "{getDie(n_sides: 3){rolls(n_rolls: 5)}}"
    # { getDie: { rolls: [ 3, 3, 3, 2, 1 ] } }

---

Next: [4. Type Hierarchies](https://github.com/prontotype-us/graphql-crashcourse/blob/master/4-type-hierarchies.litcoffee)
