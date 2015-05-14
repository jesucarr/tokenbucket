'use strict';
var Promise, TokenBucket, redis,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

Promise = require('bluebird');

redis = require('redis');


/**
  * @module tokenbucket
  * @desc A flexible rate limiter configurable with different variations of the [Token Bucket algorithm](http://en.wikipedia.org/wiki/Token_bucket), with hierarchy support, and optional persistence in Redis. Useful for limiting API requests, or other tasks that need to be throttled.
  * @author Jesús Carrera [@jesucarr](https://twitter.com/jesucarr) - [frontendmatters.com](http://frontendmatters.com)
  *
  * **Installation**
  * ```
  * npm install tokenbucket
  * ```
  *
  * @example
  * Require the library
  * ```javascript
  * var TokenBucket = require('tokenbucket');
  * ```
  * Create a new tokenbucket instance. See below for possible options.
  * ```javascript
  * var tokenBucket = new TokenBucket();
  * ```
 */


/**
  * @class
  * @alias module:tokenbucket
  * @classdesc The class that the module exports and that instantiate a new token bucket with the given options.
  *
  * @param {Object} [options] - The options object
  * @param {Number} [options.size=1] - Maximum number of tokens to hold in the bucket. Also known as the burst size.
  * @param {Number} [options.tokensToAddPerInterval=1] - Number of tokens to add to the bucket in one interval.
  * @param {Number|String} [options.interval=1000] - The time passing between adding tokens, in milliseconds or as one of the following strings: 'second', 'minute', 'hour', day'.
  * @param {Number} [options.lastFill]  - The timestamp of the last time when tokens where added to the bucket (last interval).
  * @param {Number} [options.tokensLeft=size] - By default it will initialize full of tokens, but you can set here the number of tokens you want to initialize it with.
  * @param {Boolean} [options.spread=false] - By default it will wait the interval, and then add all the tokensToAddPerInterval at once. If you set this to true, it will insert fractions of tokens at any given time, spreading the token addition along the interval.
  * @param {Number|String} [options.maxWait] - The maximum time that we would wait for enough tokens to be added, in milliseconds or as one of the following strings: 'second', 'minute', 'hour', day'. If any of the parents in the hierarchy has `maxWait`, we will use the smallest value.
  * @param {TokenBucket} [options.parentBucket] - A token bucket that will act as the parent of this bucket. Tokens removed in the children, will also be removed in the parent, and if the parent reach its limit, the children will get limited too.
  * @param {Object} [options.redis] - Options object for Redis
  * @param {String} options.redis.bucketName - The name of the bucket to reference it in Redis. This is the only required field to set Redis persistance. The `bucketName` for each bucket **must be unique**.
  * @param {external:redisClient} [options.redis.redisClient] - The [Redis client](https://github.com/mranney/node_redis#rediscreateclient) to save the bucket.
  * @param {Object} [options.redis.redisClientConfig] - [Redis client configuration](https://github.com/mranney/node_redis#rediscreateclient) to create the Redis client and save the bucket. If the `redisClient` option is set, this option will be ignored.
  * @param {Number} [options.redis.redisClientConfig.port=6379] - The connection port for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient).
  * @param {String} [options.redis.redisClientConfig.host='127.0.0.1'] - The connection host for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient)
  * @param {String} [options.redis.redisClientConfig.unixSocket] - The connection unix socket for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient)
  * @param {String} [options.redis.redisClientConfig.options] - The options for the Redis client. See [configuration instructions](https://github.com/mranney/node_redis#rediscreateclient)
  *
  * This options will be properties of the class instances. The properties `tokensLeft` and `lastFill` will get updated when we add/remove tokens.
  *
  * @example
  *
  * A filled token bucket that can hold 100 tokens, and it will add 30 tokens every minute (all at once).
  * ```javascript
  * var tokenBucket = new TokenBucket({
  *   size: 100,
  *   tokensToAddPerInterval: 30,
  *   interval: 'minute'
  * });
  * ```
  * An empty token bucket that can hold 1 token (default), and it will add 1 token (default) every 500ms, spreading the token addition along the interval (so after 250ms it will have 0.5 tokens).
  * ```javascript
  * var tokenBucket = new TokenBucket({
  *   tokensLeft: 0,
  *   interval: 500,
  *   spread: true
  * });
  * ```
  * A token bucket limited to 15 requests every 15 minutes, with a parent bucket limited to 1000 requests every 24 hours. The maximum time that we are willing to wait for enough tokens to be added is one hour.
  * ```javascript
  * var parentTokenBucket = new TokenBucket({
  *   size: 1000,
  *   interval: 'day'
  * });
  * var tokenBucket = new TokenBucket({
  *   size: 15,
  *   tokensToAddPerInterval: 15,
  *   interval: 'minute',
  *   maxWait: 'hour',
  *   parentBucket: parentBucket
  * });
  * ```
  * A token bucket limited to 15 requests every 15 minutes, with a parent bucket limited to 1000 requests every 24 hours. The maximum time that we are willing to wait for enough tokens to be added is 5 minutes.
  * ```javascript
  * var parentTokenBucket = new TokenBucket({
  *   size: 1000,
  *   interval: 'day'
  *   maxWait: 1000 * 60 * 5,
  * });
  * var tokenBucket = new TokenBucket({
  *   size: 15,
  *   tokensToAddPerInterval: 15,
  *   interval: 'minute',
  *   parentBucket: parentBucket
  * });
  * ```
  * A token bucket with Redis persistance setting the redis client.
  * ```javascript
  * redis = require('redis');
  * redisClient = redis.redisClient();
  * var tokenBucket = new TokenBucket({
  *   redis: {
  *     bucketName: 'myBucket',
  *     redisClient: redisClient
  *   }
  * });
  * ```
  * A token bucket with Redis persistance setting the redis configuration.
  * ```javascript
  * var tokenBucket = new TokenBucket({
  *   redis: {
  *     bucketName: 'myBucket',
  *     redisClientConfig: {
  *       host: 'myhost',
  *       port: 1000,
  *       options: {
  *         auth_pass: 'mypass'
  *       }
  *     }
  *   }
  * });
  * ```
  * Note that setting both `redisClient` or `redisClientConfig`, the redis client will be exposed at `tokenBucket.redis.redisClient`.
  * This means you can watch for redis events, or execute redis client functions.
  * For example if we want to close the redis connection we can execute `tokenBucket.redis.redisClient.quit()`.
 */

TokenBucket = (function() {
  var addTokens, errors;

  errors = {
    noRedisOptions: 'Redis options missing.',
    notEnoughSize: function(tokensToRemove, size) {
      return 'Requested tokens (' + tokensToRemove + ') exceed bucket size (' + size + ')';
    },
    noInfinityRemoval: 'Not possible to remove infinite tokens.',
    exceedsMaxWait: 'It will exceed maximum waiting time'
  };

  addTokens = function() {
    var now, timeSinceLastFill, tokensSinceLastFill;
    now = +new Date();
    timeSinceLastFill = Math.max(now - this.lastFill, 0);
    if (timeSinceLastFill) {
      tokensSinceLastFill = timeSinceLastFill * (this.tokensToAddPerInterval / this.interval);
    } else {
      tokensSinceLastFill = 0;
    }
    if (this.spread || (timeSinceLastFill >= this.interval)) {
      this.lastFill = now;
      return this.tokensLeft = Math.min(this.tokensLeft + tokensSinceLastFill, this.size);
    }
  };

  function TokenBucket(config) {
    this.loadSaved = bind(this.loadSaved, this);
    this.save = bind(this.save, this);
    this.removeTokensSync = bind(this.removeTokensSync, this);
    this.removeTokens = bind(this.removeTokens, this);
    var base, base1, base2, base3;
    if (config) {
      this.size = config.size, this.tokensToAddPerInterval = config.tokensToAddPerInterval, this.interval = config.interval, this.tokensLeft = config.tokensLeft, this.lastFill = config.lastFill, this.spread = config.spread, this.redis = config.redis, this.parentBucket = config.parentBucket, this.maxWait = config.maxWait;
    }
    if ((this.redis != null) && (this.redis.bucketName != null)) {
      if (this.redis.redisClient != null) {
        delete this.redis.redisClientConfig;
      } else {
        if ((base = this.redis).redisClientConfig == null) {
          base.redisClientConfig = {};
        }
        if (this.redis.redisClientConfig.unixSocket != null) {
          this.redis.redisClient = redis.createClient(this.redis.redisClientConfig.unixSocket, this.redis.redisClientConfig.options);
        } else {
          if ((base1 = this.redis.redisClientConfig).port == null) {
            base1.port = 6379;
          }
          if ((base2 = this.redis.redisClientConfig).host == null) {
            base2.host = '127.0.0.1';
          }
          if ((base3 = this.redis.redisClientConfig).options == null) {
            base3.options = {};
          }
          this.redis.redisClient = redis.createClient(this.redis.redisClientConfig.port, this.redis.redisClientConfig.host, this.redis.redisClientConfig.options);
        }
      }
    } else {
      delete this.redis;
    }
    if (this.size !== Number.POSITIVE_INFINITY) {
      if (this.size == null) {
        this.size = 1;
      }
    }
    if (this.tokensLeft == null) {
      this.tokensLeft = this.size;
    }
    if (this.tokensToAddPerInterval == null) {
      this.tokensToAddPerInterval = 1;
    }
    if (this.interval == null) {
      this.interval = 1000;
    } else if (typeof this.interval === 'string') {
      switch (this.interval) {
        case 'second':
          this.interval = 1000;
          break;
        case 'minute':
          this.interval = 1000 * 60;
          break;
        case 'hour':
          this.interval = 1000 * 60 * 60;
          break;
        case 'day':
          this.interval = 1000 * 60 * 60 * 24;
      }
    }
    if (typeof this.maxWait === 'string') {
      switch (this.maxWait) {
        case 'second':
          this.maxWait = 1000;
          break;
        case 'minute':
          this.maxWait = 1000 * 60;
          break;
        case 'hour':
          this.maxWait = 1000 * 60 * 60;
          break;
        case 'day':
          this.maxWait = 1000 * 60 * 60 * 24;
      }
    }
    if (this.lastFill == null) {
      this.lastFill = +new Date();
    }
  }


  /**
    * @desc Remove the requested number of tokens. If the bucket (and any parent buckets) contains enough tokens this will happen immediately. Otherwise, it will wait to get enough tokens.
    * @param {Number} tokensToRemove - The number of tokens to remove.
    * @returns {external:Promise}
    * @fulfil {Number} - The remaining tokens number, taking into account the parent if it has it.
    * @reject {Error} - Operational errors will be returned with the following `name` property, so they can be handled accordingly:
    * * `'NotEnoughSize'` - The requested tokens are greater than the bucket size.
    * * `'NoInfinityRemoval'` - It is not possible to remove infinite tokens, because even if the bucket has infinite size, the `tokensLeft` would be indeterminant.
    * * `'ExceedsMaxWait'` - The time we need to wait to be able to remove the tokens requested exceed the time set in `maxWait` configuration (parent or child).
    *
    * .
    * @example
    * We have some code that uses 3 API requests, so we would need to remove 3 tokens from our rate limiter bucket.
    * If we had to wait more than the specified `maxWait` to get enough tokens, we would handle that in certain way.
    * ```javascript
    * tokenBucket.removeTokens(3).then(function(remainingTokens) {
    *    console.log('10 tokens removed, ' + remainingTokens + 'tokens left');
    *    // make triple API call
    * }).catch(function (err) {
    *   console.log(err)
    *   if (err.name === 'ExceedsMaxWait') {
    *      // do something to handle this specific error
    *   }
    * });
    * ```
   */

  TokenBucket.prototype.removeTokens = function(tokensToRemove) {
    var bucketWaitInterval, calculateWaitInterval, error, hierarchyMaxWait, hierarchyWaitInterval, parentBucket, parentLastFill, resolver, wait;
    resolver = Promise.pending();
    tokensToRemove || (tokensToRemove = 1);
    if (tokensToRemove > this.size) {
      error = new Error(errors.notEnoughSize(tokensToRemove, this.size));
      Object.defineProperty(error, 'name', {
        value: 'NotEnoughSize'
      });
      resolver.reject(error);
      return resolver.promise;
    }
    if (tokensToRemove === Number.POSITIVE_INFINITY) {
      error = new Error(errors.noInfinityRemoval);
      Object.defineProperty(error, 'name', {
        value: 'NoInfinityRemoval'
      });
      resolver.reject(error);
      return resolver.promise;
    }
    addTokens.call(this);
    calculateWaitInterval = function(bucket) {
      var intervalsNeeded, timePerToken, timeSinceLastFill, tokensNeeded, waitInterval;
      tokensNeeded = tokensToRemove - bucket.tokensLeft;
      timeSinceLastFill = Math.max(+new Date() - bucket.lastFill, 0);
      if (bucket.spread) {
        timePerToken = bucket.interval / bucket.tokensToAddPerInterval;
        waitInterval = Math.ceil(tokensNeeded * timePerToken - timeSinceLastFill);
      } else {
        intervalsNeeded = tokensNeeded / bucket.tokensToAddPerInterval;
        waitInterval = Math.ceil(intervalsNeeded * bucket.interval - timeSinceLastFill);
      }
      return Math.max(waitInterval, 0);
    };
    bucketWaitInterval = calculateWaitInterval(this);
    hierarchyWaitInterval = bucketWaitInterval;
    if (this.maxWait != null) {
      hierarchyMaxWait = this.maxWait;
    }
    parentBucket = this.parentBucket;
    while (parentBucket != null) {
      hierarchyWaitInterval += calculateWaitInterval(parentBucket);
      if (parentBucket.maxWait != null) {
        if (hierarchyMaxWait != null) {
          hierarchyMaxWait = Math.min(parentBucket.maxWait, hierarchyMaxWait);
        } else {
          hierarchyMaxWait = parentBucket.maxWait;
        }
      }
      parentBucket = parentBucket.parentBucket;
    }
    if ((hierarchyMaxWait != null) && (hierarchyWaitInterval > hierarchyMaxWait)) {
      error = new Error(errors.exceedsMaxWait);
      Object.defineProperty(error, 'name', {
        value: 'ExceedsMaxWait'
      });
      resolver.reject(error);
      return resolver.promise;
    }
    wait = (function(_this) {
      return function() {
        var waitResolver;
        waitResolver = Promise.pending();
        setTimeout(function() {
          return waitResolver.resolve(true);
        }, bucketWaitInterval);
        return waitResolver.promise;
      };
    })(this);
    if (tokensToRemove > this.tokensLeft) {
      return wait().then((function(_this) {
        return function() {
          return _this.removeTokens(tokensToRemove);
        };
      })(this));
    } else {
      if (this.parentBucket) {
        parentLastFill = this.parentBucket.lastFill;
        return this.parentBucket.removeTokens(tokensToRemove).then((function(_this) {
          return function() {
            addTokens.call(_this);
            if (tokensToRemove > _this.tokensLeft) {
              _this.parentBucket.tokensLeft += tokensToRemove;
              _this.parentBucket.lastFill = parentLastFill;
              return wait().then(function() {
                return _this.removeTokens(tokensToRemove);
              });
            } else {
              _this.tokensLeft -= tokensToRemove;
              return Math.min(_this.tokensLeft, _this.parentBucket.tokensLeft);
            }
          };
        })(this));
      } else {
        this.tokensLeft -= tokensToRemove;
        resolver.resolve(this.tokensLeft);
      }
    }
    return resolver.promise;
  };


  /**
    * @desc Attempt to remove the requested number of tokens and return inmediately.
    * @param {Number} tokensToRemove - The number of tokens to remove.
    * @returns {Boolean} If it could remove the tokens inmediately it will return `true`, if not possible or needs to wait, it will return `false`.
    *
    * @example
    * ```javascript
    * if (tokenBucket.removeTokensSync(50)) {
    *   // the tokens were removed
    * } else {
    *   // the tokens were not removed
    * }
    * ```
   */

  TokenBucket.prototype.removeTokensSync = function(tokensToRemove) {
    tokensToRemove || (tokensToRemove = 1);
    addTokens.call(this);
    if (tokensToRemove > this.size) {
      return false;
    }
    if (tokensToRemove > this.tokensLeft) {
      return false;
    }
    if (this.parentBucket && !this.parentBucket.removeTokensSync(tokensToRemove)) {
      return false;
    }
    this.tokensLeft -= tokensToRemove;
    return true;
  };


  /**
    * @desc Saves the bucket lastFill and tokensLeft to Redis. If it has any parents with `redis` options, they will get saved too.
    *
    * @returns {external:Promise}
    * @fulfil {true}
    * @reject {Error} - If we call this function and we didn't set the redis options, the error will have `'NoRedisOptions'` as the `name` property, so it can be handled specifically.
    * If there is an error with Redis it will be rejected with the error returned by Redis.
    * @example
    * We have a worker process that uses 1 API requests, so we would need to remove 1 token (default) from our rate limiter bucket.
    * If we had to wait more than the specified `maxWait` to get enough tokens, we would end the worker process.
    * We are saving the bucket state in Redis, so we first load from Redis, and before exiting we save the updated bucket state.
    * Note that if it had parent buckets with Redis options set, they would get saved too.
    * ```javascript
    * tokenBucket.loadSaved().then(function () {
    *   // now the bucket has the state it had last time we saved it
    *   return tokenBucket.removeTokens().then(function() {
    *      // make API call
    *   });
    * }).catch(function (err) {
    *   if (err.name === 'ExceedsMaxWait') {
    *     tokenBucket.save().then(function () {
    *       process.kill(process.pid, 'SIGKILL');
    *     }).catch(function (err) {
    *       if (err.name == 'NoRedisOptions') {
    *         // do something to handle this specific error
    *       }
    *     });
    *   }
    * });
    * ```
   */

  TokenBucket.prototype.save = function() {
    var error, resolver, set;
    resolver = Promise.pending();
    if (!this.redis) {
      error = new Error(errors.noRedisOptions);
      Object.defineProperty(error, 'name', {
        value: 'NoRedisOptions'
      });
      resolver.reject(error);
    } else {
      set = (function(_this) {
        return function() {
          return _this.redis.redisClient.mset('tokenbucket:' + _this.redis.bucketName + ':lastFill', _this.lastFill, 'tokenbucket:' + _this.redis.bucketName + ':tokensLeft', _this.tokensLeft, function(err, reply) {
            if (err) {
              return resolver.reject(new Error(err));
            } else {
              return resolver.resolve(true);
            }
          });
        };
      })(this);
      if (this.parentBucket && (this.parentBucket.redis != null)) {
        return this.parentBucket.save().then(set);
      } else {
        set();
      }
    }
    return resolver.promise;
  };


  /**
    * @desc Loads the bucket lastFill and tokensLeft as it was saved in Redis. If it has any parents with `redis` options, they will get loaded too.
    * @returns {external:Promise}
    * @fulfil {true}
    * @reject {Error} - If we call this function and we didn't set the redis options, the error will have `'NoRedisOptions'` as the `name` property, so it can be handled specifically.
    * If there is an error with Redis it will be rejected with the error returned by Redis.
    * @example @lang off
    * See {@link module:tokenbucket#save}
   */

  TokenBucket.prototype.loadSaved = function() {
    var error, get, resolver;
    resolver = Promise.pending();
    if (!this.redis) {
      error = new Error(errors.noRedisOptions);
      Object.defineProperty(error, 'name', {
        value: 'NoRedisOptions'
      });
      resolver.reject(error);
    } else {
      get = (function(_this) {
        return function() {
          return _this.redis.redisClient.mget('tokenbucket:' + _this.redis.bucketName + ':lastFill', 'tokenbucket:' + _this.redis.bucketName + ':tokensLeft', function(err, reply) {
            if (err) {
              return resolver.reject(new Error(err));
            } else {
              if (reply[0]) {
                _this.lastFill = +reply[0];
              }
              if (reply[1]) {
                _this.tokensLeft = +reply[1];
              }
              return resolver.resolve(true);
            }
          });
        };
      })(this);
      if (this.parentBucket && (this.parentBucket.redis != null)) {
        return this.parentBucket.loadSaved().then(get);
      } else {
        get();
      }
    }
    return resolver.promise;
  };

  return TokenBucket;

})();

module.exports = TokenBucket;


/**
  * @external Promise
  * @see https://github.com/petkaantonov/bluebird
 */


/**
  * @external redisClient
  * @see https://github.com/mranney/node_redis#rediscreateclient
 */


/**
  * @external redisClientCofig
  * @see https://github.com/mranney/node_redis#rediscreateclient
 */
