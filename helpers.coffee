util = require 'util'

exports.randomChoice = (l) ->
    l[Math.floor Math.random() * l.length]

exports.descend = descend = (o, ks) ->
    if typeof ks == 'string'
        ks = ks.split('.')
    k = ks.shift()
    if k?
        descend o[k], ks
    else
        return o

# Generate a random alphanumeric string
exports.randomString = (len=8) ->
    s = ''
    while s.length < len
        s += Math.random().toString(36).slice(2, len-s.length+2)
    return s

exports.mapObj = (f, o) ->
    o_ = []
    for k, v of o
        o_[k] = f v
    o_

exports.inspect = inspect = (o) ->
    util.inspect o, colors: true, depth: null

exports.getType = (collection, {id}) ->
    collection[id]

exports.findType = (collection, query) ->
    found = []
    for item_id, item of collection
        matches = true
        for k, v of query
            if item[k] != v
                matches = false
        if matches
            found.push item
    return found

