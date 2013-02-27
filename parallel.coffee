###
#    Library: parallel.coffee
#    Author: Adam Savitzky
#    Translater: js2coffee
#    Modifier: ICHIKAWA, Yuji
#    License: Creative Commons 3.0
### 
((isNode) -> # context
    Worker = if isNode then require './worker' else window.Worker
    URL = if isNode then require './url' else window.URL
    Blob = if isNode then require './blob' else window.Blob
    Parallel = (->
        _require = (->
            state =
                files: []
                funcs: []

            isUrl = (test) ->
                r = new RegExp "^(http|https|file)://[a-zA-Z0-9-.]+.[a-zA-Z]{2,3}(:[a-zA-Z0-9]*)?/?([a-zA-Z0-9-._?,'/\\+&amp;%$#=~])*$"
                r.test test

            makeUrl = (fileName) -> if isUrl fileName then fileName else [window.location.origin, fileName].join '/'

            setter = ->
                args = (e for e in arguments)
                state.funcs = args.filter (e) -> typeof e is 'function'
                state.files = args.filter((e) -> typeof e is 'string').map makeUrl

            setter.state = state
            setter
        )()
        spawn = (->
            wrapMain = (fn) ->
                op = fn.toString()
                if isNode
                    "process.on(\"message\", function (m) { process.send({ data : JSON.stringify((#{op}).apply(process, JSON.parse(m))) }); });"
                else
                    "self.onmessage = function (e) { self.postMessage((#{op}).apply(self, e.data)); };"

            wrapFiles = (str) ->
                (if isNode
                    _require.state.files.map((f) -> "require(#{f});").join ''
                else if _require.state.files.length
                        'importScripts("' + _require.state.files.join('","') + '");'
                else '') + str

            wrapFunctions = (str) ->
                str + if _require.state.funcs.length then _require.state.funcs.map((e) -> e.toString()).join(';') + ';' else ''

            wrap = (fn) -> wrapFunctions wrapFiles wrapMain fn
            class RemoteRef
                constructor: (fn, args) ->
                    try
                        str = wrap fn
                        blob = new Blob [str], type: 'text/javascript'
                        url = URL.createObjectURL blob
                        worker = new Worker url
                        worker.onmessage = @onWorkerMsg
                        @worker = worker
                        @worker.ref = this
                        @worker.postMessage if isNode
                                JSON.stringify [].concat args
                            else
                                [].concat args
                    catch e
                        console.error e if console? and console.error?
                        @onWorkerMsg data: fn.apply(window, [].concat args)

                onWorkerMsg: (e) =>
                    if isNode
                        @data = JSON.parse e.data
                        @worker.terminate()
                    else
                        @data = e.data

                data: `undefined`
                fetch: (cb) ->
                    return if @data is '___terminated'
                    if @data
                        if cb? then cb @data else @data
                    else
                        setTimeout((=> @fetch cb), 0) and `undefined`

                terminate: ->
                    @data = '___terminated'
                    @worker.terminate()

            (fn, args) -> new RemoteRef fn, args
        )()
        mapreduce = (->
            class DistributedProcess
                constructor: (@mapper, @reducer, @chunks) -> @refs = @chunks.map (chunk) => spawn @mapper, [].concat chunk

                fetch: (cb) ->
                    results = @fetchRefs()
                    if results.every((e) -> typeof e isnt 'undefined')
                        return if cb?
                                cb results.reduce @reducer
                            else
                                results.reduce @reducer
                    setTimeout (=> @fetch cb), 100
                    null

                fetchRefs: (cb) -> @refs.map (ref) -> ref.fetch cb or `undefined`

                terminate: (n) ->
                    if n isnt `undefined`
                        @refs[n].terminate()
                    else
                        @refs.map (e) -> e.terminate()

            (mapper, reducer, chunks, cb) ->
                d = new DistributedProcess mapper, reducer, chunks
                d.fetch cb
                d
        )()
        mapreduce: mapreduce
        spawn: spawn
        require: _require
    )()
    if isNode
        @exports = Parallel
    else
        @Parallel = Parallel
# isNode
).call if typeof module isnt "undefined" and module.exports then module else window
