graphql = require 'graphql'
{randomChoice, inspector} = require './helpers'

object_schema = """
users
    name string
    email string
    interactions interactions < user_id

interactions
    user users > user_id
    assessment assessments > assessment_id

assessments
    name string
    items items < assessment_id

items
    body string
"""

tokenizeSchema = (object_schema) ->
    object_schema.split('\n\n').map tokenizeSection

tokenizeSection = (section) ->
    section = section.split('\n')
    key = section.shift()
    lines = section.map (line) ->
        line.trim().split(' ')
    [key, lines]

parseSection = ([key, lines]) ->
    {
        name: key
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

inspector('tokenized') tokenized = tokenizeSchema object_schema
inspector('parsed') parsed = tokenized.map parseSection

# -----

graphql_schema = new graphql.GraphQLSchema {query}

runQuery = (query) ->
    graphql.graphql(graphql_schema, query)
        .then ({errors ,data}) ->
            errors or data

runQuery "{}"
    .then inspector 'ideal case'

