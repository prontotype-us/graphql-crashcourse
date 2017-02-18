graphql = require 'graphql'
{randomChoice, inspector} = require './helpers'

quotes = ['hi there', 'this is testing', 'what is this']

query = new graphql.GraphQLObjectType
    name: 'Query'
    fields:
        randomNumber:
            type: graphql.GraphQLFloat
            resolve: -> Math.random()
        randomQuote:
            type: graphql.GraphQLString
            resolve: -> randomChoice quotes

graphql_schema = new graphql.GraphQLSchema {query}

runQuery = (query) ->
    graphql.graphql(graphql_schema, query)
        .then ({errors ,data}) ->
            errors or data

runQuery "{randomNumber, randomQuote}"
    .then inspector 'random number and quote'

