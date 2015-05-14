[![Dependency status](https://img.shields.io/david/jesucarr/tokenbucket.svg?style=flat)](https://david-dm.org/jesucarr/tokenbucket)
[![devDependency Status](https://img.shields.io/david/dev/jesucarr/tokenbucket.svg?style=flat)](https://david-dm.org/jesucarr/tokenbucket#info=devDependencies)
[![Build Status](https://img.shields.io/travis/jesucarr/tokenbucket.svg?style=flat&branch=master)](https://travis-ci.org/jesucarr/tokenbucket)
[![Test Coverage](https://img.shields.io/coveralls/jesucarr/tokenbucket.svg?style=flat&branch=master)](https://coveralls.io/r/jesucarr/tokenbucket)
[![NPM](https://nodei.co/npm/tokenbucket.svg?style=flat)](https://npmjs.org/package/tokenbucket)

<a name="module_tokenbucket"></a>
## tokenbucket
A flexible rate limiter configurable with different variations of the [Token Bucket algorithm](http://en.wikipedia.org/wiki/Token_bucket), with hierarchy support, and optional persistence in Redis. Useful for limiting API requests, or other tasks that need to be throttled.

**Author:** Jesús Carrera [@jesucarr](https://twitter.com/jesucarr) - [frontendmatters.com](http://frontendmatters.com)

**Installation**
```
npm install tokenbucket
```  
**Example**  
Require the library
```javascript
var TokenBucket = require('tokenbucket');
```
Create a new tokenbucket instance. See below for possible options.
```javascript
var tokenBucket = new TokenBucket();
```

* [tokenbucket](#module_tokenbucket)
  * [TokenBucket](#exp_module_tokenbucket--TokenBucket) ⏏
    * [new TokenBucket([options])](#new_module_tokenbucket--TokenBucket_new)
    * [.removeTokens(tokensToRemove)](#module_tokenbucket--TokenBucket#removeTokens) ⇒ <code>[Promise](https://github.com/petkaantonov/bluebird)</code>
    * [.removeTokensSync(tokensToRemove)](#module_tokenbucket--TokenBucket#removeTokensSync) ⇒ <code>Boolean</code>
    * [.save()](#module_tokenbucket--TokenBucket#save) ⇒ <code>[Promise](https://github.com/petkaantonov/bluebird)</code>
    * [.loadSaved()](#module_tokenbucket--TokenBucket#loadSaved) ⇒ <code>[Promise](https://github.com/petkaantonov/bluebird)</code>

<a name="exp_module_tokenbucket--TokenBucket"></a>
### TokenBucket ⏏
The class that the module exports and that instantiate a new token bucket with the given options.

**Kind**: Exported class  
<a name="new_module_tokenbucket--TokenBucket_new"></a>
#### new TokenBucket([options])
**Params**
- [options] <code>Object</code> - The options object
  - [.size] <code>Number</code> <code> = 1</code> - Maximum number of tokens to hold in the bucket. Also known as the burst size.
  - [.tokensToAddPerInterval] <code>Number</code> <code> = 1</code> - Number of tokens to add to the bucket in one interval.
  - [.interval] <code>Number</code> | <code>String</code> <code> = 1000</code> - The time passing between adding tokens, in milliseconds or as one of the following strings: 'second', 'minute', 'hour', day'.
  - [.lastFill] <code>Number</code> - The timestamp of the last time when tokens where added to the bucket (last interval).
  - [.tokensLeft] <code>Number</code> <code> = size</code> - By default it will initialize full of tokens, but you can set here the number of tokens you want to initialize it with.
  - [.spread] <code>Boolean</code> <code> = false</code> - By default it will wait the interval, and then add all the tokensToAddPerInterval at once. If you set this to true, it will insert fractions of tokens at any given time, spreading the token addition along the interval.
  - [.maxWait] <code>Number</code> | <code>String</code> - The maximum time that we would wait for enough tokens to be added, in milliseconds or as one of the following strings: 'second', 'minute', 'hour', day'. If any of the parents in the hierarchy has `maxWait`, we will use the smallest value.
  - [.parentBucket] <code>TokenBucket</code> - A token bucket that will act as the parent of this bucket. Tokens removed in the children, will also be removed in the parent, and if the parent reach its limit, the children will get limited too.
  - [.redis] <code>Object</code> - Options object for Redis
    - .bucketName <code>String</code> - The name of the bucket to reference it in Redis. This is the only required field to set Redis persistance. The `bucketName` for each bucket **must be unique**.
    - [.redisClient] <code>[redisClient](https://github.com/mranney/node_redis#rediscreateclient)</code> - The [Redis client](https://github.com/mranney/node_redis#rediscreateclient) to save the bucket.
    - [.redisClientConfig] <code>Object</code> - [Redis client configuration](https://github.com/mranney/node_redis#rediscreateclient) to create the Redis client and save the bucket. If the `redisClient` option is set, this option will be ignored.
      - [.port] <code>Number</code> <code> = 6379</code> - The connection port for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient).
      - [.host] <code>String</code> <code> = &#x27;127.0.0.1&#x27;</code> - The connection host for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient)
      - [.unixSocket] <code>String</code> - The connection unix socket for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient)
      - [.options] <code>String</code> - The options for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient)

This options will be properties of the class instances. The properties `tokensLeft` and `lastFill` will get updated when we add/remove tokens.

**Example**  
A filled token bucket that can hold 100 tokens, and it will add 30 tokens every minute (all at once).
```javascript
var tokenBucket = new TokenBucket({
  size: 100,
  tokensToAddPerInterval: 30,
  interval: 'minute'
});
```
An empty token bucket that can hold 1 token (default), and it will add 1 token (default) every 500ms, spreading the token addition along the interval (so after 250ms it will have 0.5 tokens).
```javascript
var tokenBucket = new TokenBucket({
  tokensLeft: 0,
  interval: 500,
  spread: true
});
```
A token bucket limited to 15 requests every 15 minutes, with a parent bucket limited to 1000 requests every 24 hours. The maximum time that we are willing to wait for enough tokens to be added is one hour.
```javascript
var parentTokenBucket = new TokenBucket({
  size: 1000,
  interval: 'day'
});
var tokenBucket = new TokenBucket({
  size: 15,
  tokensToAddPerInterval: 15,
  interval: 'minute',
  maxWait: 'hour',
  parentBucket: parentBucket
});
```
A token bucket limited to 15 requests every 15 minutes, with a parent bucket limited to 1000 requests every 24 hours. The maximum time that we are willing to wait for enough tokens to be added is 5 minutes.
```javascript
var parentTokenBucket = new TokenBucket({
  size: 1000,
  interval: 'day'
  maxWait: 1000 * 60 * 5,
});
var tokenBucket = new TokenBucket({
  size: 15,
  tokensToAddPerInterval: 15,
  interval: 'minute',
  parentBucket: parentBucket
});
```
A token bucket with Redis persistance setting the redis client.
```javascript
redis = require('redis');
redisClient = redis.redisClient();
var tokenBucket = new TokenBucket({
  redis: {
    bucketName: 'myBucket',
    redisClient: redisClient
  }
});
```
A token bucket with Redis persistance setting the redis configuration.
```javascript
var tokenBucket = new TokenBucket({
  redis: {
    bucketName: 'myBucket',
    redisClientConfig: {
      host: 'myhost',
      port: 1000,
      options: {
        auth_pass: 'mypass'
      }
    }
  }
});
```
Note that setting both `redisClient` or `redisClientConfig`, the redis client will be exposed at `tokenBucket.redis.redisClient`.
This means you can watch for redis events, or execute redis client functions.
For example if we want to close the redis connection we can execute `tokenBucket.redis.redisClient.quit()`.
<a name="module_tokenbucket--TokenBucket#removeTokens"></a>
#### tokenBucket.removeTokens(tokensToRemove) ⇒ <code>[Promise](https://github.com/petkaantonov/bluebird)</code>
Remove the requested number of tokens. If the bucket (and any parent buckets) contains enough tokens this will happen immediately. Otherwise, it will wait to get enough tokens.

**Kind**: instance method of <code>[TokenBucket](#exp_module_tokenbucket--TokenBucket)</code>  
**Fulfil**: <code>Number</code> - The remaining tokens number, taking into account the parent if it has it.  
**Reject**: <code>Error</code> - Operational errors will be returned with the following `name` property, so they can be handled accordingly:
* `'NotEnoughSize'` - The requested tokens are greater than the bucket size.
* `'NoInfinityRemoval'` - It is not possible to remove infinite tokens, because even if the bucket has infinite size, the `tokensLeft` would be indeterminant.
* `'ExceedsMaxWait'` - The time we need to wait to be able to remove the tokens requested exceed the time set in `maxWait` configuration (parent or child).

.  
**Params**
- tokensToRemove <code>Number</code> - The number of tokens to remove.

**Example**  
We have some code that uses 3 API requests, so we would need to remove 3 tokens from our rate limiter bucket.
If we had to wait more than the specified `maxWait` to get enough tokens, we would handle that in certain way.
```javascript
tokenBucket.removeTokens(3).then(function(remainingTokens) {
   console.log('10 tokens removed, ' + remainingTokens + 'tokens left');
   // make triple API call
}).catch(function (err) {
  console.log(err)
  if (err.name === 'ExceedsMaxWait') {
     // do something to handle this specific error
  }
});
```
<a name="module_tokenbucket--TokenBucket#removeTokensSync"></a>
#### tokenBucket.removeTokensSync(tokensToRemove) ⇒ <code>Boolean</code>
Attempt to remove the requested number of tokens and return inmediately.

**Kind**: instance method of <code>[TokenBucket](#exp_module_tokenbucket--TokenBucket)</code>  
**Returns**: <code>Boolean</code> - If it could remove the tokens inmediately it will return `true`, if not possible or needs to wait, it will return `false`.  
**Params**
- tokensToRemove <code>Number</code> - The number of tokens to remove.

**Example**  
```javascript
if (tokenBucket.removeTokensSync(50)) {
  // the tokens were removed
} else {
  // the tokens were not removed
}
```
<a name="module_tokenbucket--TokenBucket#save"></a>
#### tokenBucket.save() ⇒ <code>[Promise](https://github.com/petkaantonov/bluebird)</code>
Saves the bucket lastFill and tokensLeft to Redis. If it has any parents with `redis` options, they will get saved too.

**Kind**: instance method of <code>[TokenBucket](#exp_module_tokenbucket--TokenBucket)</code>  
**Fulfil**: <code>true</code>  
**Reject**: <code>Error</code> - If we call this function and we didn't set the redis options, the error will have `'NoRedisOptions'` as the `name` property, so it can be handled specifically.
If there is an error with Redis it will be rejected with the error returned by Redis.  
**Example**  
We have a worker process that uses 1 API requests, so we would need to remove 1 token (default) from our rate limiter bucket.
If we had to wait more than the specified `maxWait` to get enough tokens, we would end the worker process.
We are saving the bucket state in Redis, so we first load from Redis, and before exiting we save the updated bucket state.
Note that if it had parent buckets with Redis options set, they would get saved too.
```javascript
tokenBucket.loadSaved().then(function () {
  // now the bucket has the state it had last time we saved it
  return tokenBucket.removeTokens().then(function() {
     // make API call
  });
}).catch(function (err) {
  if (err.name === 'ExceedsMaxWait') {
    tokenBucket.save().then(function () {
      process.kill(process.pid, 'SIGKILL');
    }).catch(function (err) {
      if (err.name == 'NoRedisOptions') {
        // do something to handle this specific error
      }
    });
  }
});
```
<a name="module_tokenbucket--TokenBucket#loadSaved"></a>
#### tokenBucket.loadSaved() ⇒ <code>[Promise](https://github.com/petkaantonov/bluebird)</code>
Loads the bucket lastFill and tokensLeft as it was saved in Redis. If it has any parents with `redis` options, they will get loaded too.

**Kind**: instance method of <code>[TokenBucket](#exp_module_tokenbucket--TokenBucket)</code>  
**Fulfil**: <code>true</code>  
**Reject**: <code>Error</code> - If we call this function and we didn't set the redis options, the error will have `'NoRedisOptions'` as the `name` property, so it can be handled specifically.
If there is an error with Redis it will be rejected with the error returned by Redis.  
**Example**  
See [save](#module_tokenbucket--TokenBucket#save)

## Testing

    npm test

## Development and Contributing

The source code is in CoffeeScript, to compile automatically when you save, run

    gulp

Documentation is inline, using [jsdoc-to-markdown](https://github.com/75lb/jsdoc-to-markdown). To update the README.md file just run

    gulp doc

Contributions are welcome! Pull requests should have 100% code coverage.

## Credits

Originally inspired by [limiter](https://github.com/jhurliman/node-rate-limiter).

## License

The MIT License (MIT)

Copyright 2015 Jesús Carrera - [frontendmatters.com](http://frontendmatters.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
