/* Carrot -- Copyright (C) 2012 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.carrot
{
	import com.carrot.adobe.crypto.*;
	import com.carrot.adobe.serialization.json.JSON;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.net.URLVariables;
	import flash.net.URLLoader;
	import flash.events.Event;
	import mx.utils.UIDUtil;
	import mx.utils.Base64Encoder;
	import flash.utils.ByteArray;
	import flash.events.HTTPStatusEvent;
	import ru.inspirit.net.MultipartURLLoader;
	import ru.inspirit.net.events.MultipartURLLoaderEvent;


	/**
	 * Allows you to interact with the Carrot service from your Flash application.
	 *
	 * <p>All calls to the Carrot service are asynchronous and have an optional callback function
	 * which will be called upon completion of the API call.</p>
	 */
	public class Carrot
	{
		public static const NOT_AUTHORIZED:String = "Carrot user has not authorized application.";
		public static const NOT_CREATED:String = "Carrot user does not exist.";
		public static const UNKNOWN:String = "Carrot user status unknown.";
		public static const READ_ONLY:String = "Carrot user has not granted 'publish_actions' permission.";
		public static const AUTHORIZED:String = "Carrot user authorized.";
		public static const OK:String = "Operation successful.";
		public static const ERROR:String = "Operation unsuccessful.";
		public static const BAD_SECRET:String = "Operation unsuccessful (bad Carrot secret).";

		/**
		 * Create a new Carrot instance.
		 *
		 * @param appId      Facebook Application Id for your application.
		 * @param appSecret  Carrot Application Secret for your application.
		 * @param udid       A per-user unique identifier. We suggest using email address or the Facebook 'third_party_id'.
		 */
		public function Carrot(appId:String, appSecret:String, udid:String, hostname:String = "gocarrot.com") {
			_appId = appId;
			_appSecret = appSecret;
			_hostname = hostname;
			_udid = udid;
			_status = UNKNOWN;
		}

		/**
		 * The Carrot authentication status for the active user.
		 */
		public function get status():String {
			return _status;
		}

		/**
		 * Validate a user with the Carrot service.
		 *
		 * @param accessTokenOrFacebookId  The Facebook user access token or Facebook Id for the user.
		 * @param callback                 A function which will be called upon completion of the user validation with the authentication status of the active user.
		 */
		public function validateUser(accessTokenOrFacebookId:String, callback:Function = null):Boolean {
			var params:Object = {
				access_token: accessTokenOrFacebookId,
				api_key: _udid
			}
			return httpRequest(URLRequestMethod.POST, "/games/" + _appId + "/users.json", params, function(event:HTTPStatusEvent):void {
				switch(event.status) {
					case 201: _status = AUTHORIZED; break;
					case 401: _status = READ_ONLY; break;
					case 404: _status = NOT_AUTHORIZED; break;
					default: _status = UNKNOWN; break;
				}
				if(callback != null) {
					callback(_status);
				}
			});
		}

		/**
		 * Post an achievement to the Carrot service.
		 *
		 * @param achievementId Carrot achivement id of the achievement to post.
		 * @param callback      A function which will be called upon completion of the achievement post.
		 */
		public function postAchievement(achievementId:String, callback:Function = null):Boolean {
			return postSignedRequest("/me/achievements.json", {achievement_id: achievementId}, callback);
		}

		/**
		 * Post a high score to the Carrot service.
		 *
		 * @param score     High score value to post.
		 * @param callback  A function which will be called upon completion of the high score post.
		 */
		public function postHighScore(score:uint, callback:Function = null):Boolean {
			return postSignedRequest("/me/scores.json", {value: score}, callback);
		}

		/**
		 * Post an Open Graph action to the Carrot service.
		 *
		 * <p>If creating an object, you are required to include 'object_type' in objectProperties.</p>
		 *
		 * @param actionId          Carrot action id.
		 * @param objectInstanceId  Object instance id of the Carrot object type to create or post; use <code>null</code> if you are creating a throw-away object.
		 * @param actionProperties  Properties to be sent along with the Carrot action, or <code>null</code>.
		 * @param objectProperties  Properties for the new object, if creating an object, or <code>null</code>.
		 * @param callback          A function which will be called upon completion of the action post.
		 */
		public function postAction(actionId:String, objectInstanceId:String, actionProperties:Object = null, objectProperties:Object = null, callback:Function = null):Boolean {
			if(objectInstanceId === null && objectProperties === null) {
				throw new Error("objectProperties may not be null if objectInstanceId is null");
			}
			else if(objectProperties !== null && !objectProperties.hasOwnProperty("object_type")) {
				throw new Error("objectProperties must contain 'object_type'");
			}

			var params:Object = {
				action_id: actionId,
				action_properties: com.carrot.adobe.serialization.json.JSON.encode(actionProperties === null ? {} : actionProperties),
				object_properties: com.carrot.adobe.serialization.json.JSON.encode(objectProperties === null ? {} : objectProperties)
			}
			if(objectInstanceId != null) {
				params.object_instance_id = objectInstanceId;
			}
			return postSignedRequest("/me/actions.json", params, callback);
		}

		/**
		 * Post a 'Like' action that likes the Game's Facebook Page.
		 *
		 * @param callback A function which will be called upon completion of the action post.
		 */
		public function likeGame(callback:Function = null):Boolean {
			return postSignedRequest("/me/like.json", {object: "game"}, callback);
		}

		/**
		 * Post a 'Like' action that likes the Publisher's Facebook Page.
		 *
		 * @param callback A function which will be called upon completion of the action post.
		 */
		public function likePublisher(callback:Function = null):Boolean {
			return postSignedRequest("/me/like.json", {object: "publisher"}, callback);
		}

		/**
		 * Post a 'Like' action that likes an achievement.
		 *
		 * @param achievementId The achievement identifier.
		 * @param callback      A function which will be called upon completion of the action post.
		 */
		public function likeAchievement(achievementId:String, callback:Function = null):Boolean {
			return postSignedRequest("/me/like.json", {object: "achievement:" + achievementId}, callback);
		}

		/**
		 * Post a 'Like' action that likes an Open Graph object.
		 *
		 * @param objectInstanceId The instance id of the Carrot object.
		 * @param callback         A function which will be called upon completion of the action post.
		 */
		public function likeObject(objectInstanceId:String, callback:Function = null):Boolean {
			return postSignedRequest("/me/like.json", {object: "object:" + objectInstanceId}, callback);
		}

		private function postSignedRequest(endpoint:String, queryParams:Object, callback:Function):Boolean {
			var timestamp:Date = new Date();

			var urlParams:Object = {
				request_date: Math.round(timestamp.getTime() / 1000),
				request_id: UIDUtil.createUID()
			};

			for(var k:String in queryParams) {
				urlParams[k] = queryParams[k];
			}
			return makeSignedRequest(endpoint, URLRequestMethod.POST, urlParams, callback);
		}

		private function makeSignedRequest(endpoint:String, method:String, queryParams:Object, callback:Function):Boolean {
			var urlParams:Object = {
				api_key: _udid,
				game_id: _appId
			};

			for(var k:String in queryParams) {
				urlParams[k] = queryParams[k];
			}

			var urlParamKeys:Array = [];
			for(k in urlParams) {
				urlParamKeys.push(k);
			}
			urlParamKeys.sort();

			var urlString:String = "";
			for each(k in urlParamKeys) {
				urlString += k + "=" + urlParams[k] + "&";
			}
			urlString = urlString.slice(0, urlString.length - 1);

			var signString:String = method + "\n" + _hostname + "\n" + endpoint + "\n" + urlString;
			var digest:String = HMAC.hash(_appSecret, signString, SHA256);
			var hashBytes:ByteArray = new ByteArray();
			for(var i:uint = 0; i < digest.length; i += 2)
				hashBytes.writeByte(parseInt(digest.charAt(i) + digest.charAt(i + 1), 16));
			var encoder:Base64Encoder = new Base64Encoder();
			encoder.encodeBytes(hashBytes);
			urlParams.sig = encoder.toString();

			return httpRequest(method, endpoint, urlParams, callback);
		}

		private function httpRequest(method:String, endpoint:String, urlParams:Object, callback:Function):Boolean {
			var loader:MultipartURLLoader = new MultipartURLLoader();
			if(urlParams != null) {
				for(var k:String in urlParams) {
					loader.addVariable(k, urlParams[k]);
				}
			}

			if(callback != null) {
				loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(event:HTTPStatusEvent):void {
					var apiCallStatus:String = UNKNOWN;
					switch(event.status) {
						case 200:
						case 201: _status = AUTHORIZED; apiCallStatus = OK; break;
						case 401: apiCallStatus = _status = READ_ONLY; break;
						case 403: apiCallStatus = _status = BAD_SECRET; break;
						case 405: apiCallStatus = _status = NOT_AUTHORIZED; break;
					}
					if(method === URLRequestMethod.POST && callback != null) {
						callback(apiCallStatus);
					}
				});
			}

			try {
				loader.load("https://" + _hostname + endpoint);
				return true;
			}
			catch(error:Error) {
				trace(error);
			}
			return false;
		}

		private var _udid:String;
		private var _appId:String;
		private var _hostname:String;
		private var _appSecret:String;
		private var _status:String;
	}
}
