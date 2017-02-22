# 9. Advanced Queries with Arguments, Fragments, and Directives

Here we cover a few extra features of the Query language. The common theme of these features is allowing us to build more reusable queries. 

    graphql = require 'graphql'
    {inspect, getType, findType} = require './helpers'

## Schema

The schema is basic, with Users and their Pets, and some relationships between:

    graphql_schema = graphql.buildSchema """

    type User {
        id: ID
        name: String
        pets: [Pet]
        friends: [User]
    }

    type Pet {
        id: ID
        kind: String
        name: String
        owner: User
    }

    type Query {
        user(id: ID!): User
        pet(id: ID!): Pet
        users: [User]
        pets: [Pet]
    }

    """

## Resolvers

Nothing new here, we're going back to using classes for readability:

    class User
        constructor: ({id, name, friend_ids}) ->
            console.log "new User(id: #{id}, name: '#{name}')"
            @id = id
            @name = name
            @friend_ids = friend_ids

        pets: ->
            findType pets, {owner_id: @id}

        friends: ->
            @friend_ids.map (friend_id) ->
                getType users, {id: friend_id}

    class Pet
        constructor: ({id, kind, name, owner_id}) ->
            console.log "new Pet(id: #{id}, kind: '#{kind}', name: '#{name}', owner_id: #{owner_id})"
            @id = id
            @kind = kind
            @name = name
            @owner_id = owner_id

        owner: ->
            getUser {id: @owner_id}

And another static database:

    users = {
        0: new User {id: 0, name: 'joe', friend_ids: [2]}
        1: new User {id: 1, name: 'fred', friend_ids: [0]}
        2: new User {id: 2, name: 'sam', friend_ids: [0, 1]}
    }

    pets = {
        0: new Pet {id: 0, kind: 'cat', name: 'snuffy', owner_id: 0}
        1: new Pet {id: 1, kind: 'dog', name: 'wiggles', owner_id: 1}
        2: new Pet {id: 2, kind: 'cat', name: 'floofer', owner_id: 1}
    }

The `getType` and `findType` resolvers were imported from `helpers`.

    graphql_root = {
        user: getType.bind null, users
        users: findType.bind null, users
        pet: getType.bind null, pets
        pets: findType.bind null, pets
    }

## Querying

Here's where things get interesting. First notice that the `runQuery` function now has another argument `vars`, which is being passed to the main `graphql` function.

    runQuery = (query, vars={}) ->
        graphql.graphql(graphql_schema, query, graphql_root, null, vars)
            .then ({errors, data}) ->
                console.log inspect(errors or data)

### Named queries

Before we get into these features, a note about queries. So far we have been starting queries straight from the opening bracket, but in fact that's a shortcut. The full form of a query is `query [name](args){ ... }`, simliar to how we start a mutation with `mutation{ ... }` (and mutations can be named and have arguments too). The name is just for you and your developer friends, to know exactly what the query is about.

In other words, these queries are exactly the same:

    runQuery """
    {
        user(id: 0){id, name}
    }
    """

    runQuery """
    query getSomeUser {
        user(id: 0){id, name}
    }
    """

We'll be using named queries from now on.

### Query  variables

Often when querying we have a specific object ID, or a filter or something to pass to the query. Templating values into the query string would be as bad as templating into an SQL string. So instead we can use placeholder variables in the query, pass values to the `vars` argument, and let the GraphQL engine deal with it.

Variables are represented as `$variable` in the query. Any variables used must be declared up in the top `query` section, with their expected type.

    runQuery """
    query getSomeUserById($user_id: ID!) {
        user(id: $user_id){
            id, name, pets{kind, name}
        }
    }
    """, {user_id: 1}

This is a first step towards reusable queries, as we can save the query string and run it with different values:

    getSomeUserById = """
    query getSomeUserById($user_id: ID!) {
        user(id: $user_id){
            id, name, pets{kind, name}
        }
    }
    """
    
    runQuery getSomeUserById, {user_id: 1}
    runQuery getSomeUserById, {user_id: 2}

### Named fields

What if we want multiple objects of the same type at once, e.g. `{user(id: 0), user(id: 1)}`? The default behavior is to return fields as they are named in the query, but that wouldn't work here because the two keys `user` would conflict. Instead we can set explicit names of fields to be returned, by prefixing them with `[name]: `:

    getTwoUsers = """
    query getTwoUsers($uid1: ID!, $uid2: ID!) {
        u1: user(id: $uid1){id, name, pets{kind, name}},
        u2: user(id: $uid2){id, name, pets{kind, name}}
    }
    """

    runQuery getTwoUsers, {uid1: 1, uid2: 2}
    # { u1:
    #    { id: '1',
    #      name: 'fred',
    #      pets:
    #       [ { kind: 'dog', name: 'wiggles' },
    #         { kind: 'cat', name: 'floofer' } ] },
    #   u2: { id: '2', name: 'sam', pets: [] } }

### Query fragments

When getting two of the same thing, we had to repeat the whole set of fields to return. That might be a standard shape that we want to use elsewhere, without repeating ourselves. Fragments make this possible. They encourage reusability *within* the query.

Fragments are declared as `fragment [name] on [type]` with a set of fields. To use, they are added to fields of an appropriate type with syntax similar to the spread operator, e.g. `{...UserFragment}`, and they will be expanded from there. Note that you can add fields beside a fragment as well.

    getTwoUsersFragmented = """
    query getTwoUsersFragmented($uid1: ID!, $uid2: ID!) {
        u1: user(id: $uid1){...UserFragment, friends{name}},
        u2: user(id: $uid2){...UserFragment}
    }
    fragment UserFragment on User {
        id, name, pets{kind, name}
    }
    """

    runQuery getTwoUsersFragmented, {uid1: 0, uid2: 1}
    # { u1:
    #    { id: '0',
    #      name: 'joe',
    #      pets: [ { kind: 'cat', name: 'snuffy' } ],
    #      friends: [ { name: 'sam' } ] },
    #   u2:
    #    { id: '1',
    #      name: 'fred',
    #      pets:
    #       [ { kind: 'dog', name: 'wiggles' },
    #         { kind: 'cat', name: 'floofer' } ] } }


### Query directives

The last feature allows us to reuse a single query for multiple purposes. "Directives" are special functions run on arguments that either `@include` or `@skip` certain fields. This can be used to create a more minimal or more expanded version of a query.

In this example, the users' friends are fetched by default, but skipped if `hide_friends` is true - while pets are not fetched by default, unless you pass `show_pets`.

    usersWithFriendsAndPets = """
    query usersWithFriendsAndPets($hide_friends: Boolean = false, $show_pets: Boolean = false) {
        u1: user(id: 0){...UserFragment},
        u2: user(id: 1){...UserFragment}
    }
    fragment UserFragment on User {
        name,
        friends @skip(if: $hide_friends){name},
        pets @include(if: $show_pets){...PetFragment}
    }
    fragment PetFragment on Pet {
        kind, name
    }
    """

    runQuery usersWithFriendsAndPets, {hide_friends: true} # No friends or pets
    # { u1: { name: 'joe' }, u2: { name: 'fred' } }

    runQuery usersWithFriendsAndPets, {show_pets: true} # All friends and pets
    # { u1:
    #    { name: 'joe',
    #      friends: [ { name: 'sam' } ],
    #      pets: [ { kind: 'cat', name: 'snuffy' } ] },
    #   u2:
    #    { name: 'fred',
    #      friends: [ { name: 'joe' } ],
    #      pets:
    #       [ { kind: 'dog', name: 'wiggles' },
    #         { kind: 'cat', name: 'floofer' } ] } }

