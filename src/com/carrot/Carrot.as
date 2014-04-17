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
	import flash.utils.ByteArray;
	import flash.display.BitmapData;
	import flash.system.Capabilities;
	import flash.events.HTTPStatusEvent;
	import ru.inspirit.net.MultipartURLLoader;
	import ru.inspirit.net.events.MultipartURLLoaderEvent;
	import com.laiyonghao.Uuid;
	import com.sociodox.utils.Base64;

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

		public static const SDKVersion:String = "1.1";

		/**
		 * Create a new Carrot instance.
		 *
		 * @param appId      Facebook Application Id for your application.
		 * @param appSecret  Carrot Application Secret for your application.
		 * @param udid       A per-user unique identifier. We suggest using email address or the Facebook 'third_party_id'.
		 * @param versionId  A string specifying the current version of your application for metrics reporting.
		 */
		public function Carrot(appId:String, appSecret:String, udid:String, versionId:String = "unknown") {
			if(appId === null) {
				throw new Error("appId must not be null");
			}
			else if(appSecret === null) {
				throw new Error("appSecret must not be null");
			}
			else if(udid === null) {
				throw new Error("udid must not be null");
			}

			_appId = appId;
			_appSecret = appSecret;
			_udid = udid;
			_status = UNKNOWN;
			_appVersion = versionId;

			// Perform services discovery
			if(!performServicesDiscovery()) {
				trace("Could not perform services discovery. Carrot is offline.");
			}

			makeSignedRequest(_metricsHostname, "/app_opened.json", URLRequestMethod.POST, {}, null, null);
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
			if(accessTokenOrFacebookId === null) {
				throw new Error("accessTokenOrFacebookId must not be null");
			}

			var params:Object = {
				access_token: accessTokenOrFacebookId,
				api_key: _udid
			}
			addCommonPayloadFields(params);
			return httpRequest(_authHostname, URLRequestMethod.POST, "/games/" + _appId + "/users.json", params, null, function(event:HTTPStatusEvent):void {
				switch(event.status) {
					case 201: _status = AUTHORIZED; break;
					case 401: _status = READ_ONLY; break;
					case 404: _status = NOT_AUTHORIZED; break;
					default: _status = UNKNOWN; break;
				}
				if(callback !== null) {
					callback(_status);
				}
			}, true);
		}

		/**
		 * Post an achievement to the Carrot service.
		 *
		 * @param achievementId Carrot achivement id of the achievement to post.
		 * @param callback      A function which will be called upon completion of the achievement post.
		 */
		public function postAchievement(achievementId:String, callback:Function = null):Boolean {
			if(achievementId === null) {
				throw new Error("achievementId must not be null");
			}
			return postSignedRequest("/me/achievements.json", {achievement_id: achievementId}, null, callback);
		}

		/**
		 * Post a high score to the Carrot service.
		 *
		 * @param score     High score value to post.
		 * @param callback  A function which will be called upon completion of the high score post.
		 */
		public function postHighScore(score:uint, callback:Function = null):Boolean {
			return postSignedRequest("/me/scores.json", {value: score}, null, callback);
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
		 * @param bitmapData        BitmapData to upload, if creating an object, or <code>null</code>.
		 * @param callback          A function which will be called upon completion of the action post.
		 */
		public function postAction(actionId:String, objectInstanceId:String, actionProperties:Object = null, objectProperties:Object = null, bitmapData:BitmapData = null, callback:Function = null):Boolean {
			if(actionId === null) {
				throw new Error("actionId must not be null");
			}
			else if(objectInstanceId === null && objectProperties === null) {
				throw new Error("objectProperties may not be null if objectInstanceId is null");
			}
			else if(objectProperties !== null && !objectProperties.hasOwnProperty("object_type")) {
				throw new Error("objectProperties must contain 'object_type'");
			}
			else if(objectProperties === null && bitmapData !== null) {
				throw new Error("objectProperties must not be null if bitmapData is included.");
			}

			var params:Object = {
				action_id: actionId,
				action_properties: com.carrot.adobe.serialization.json.JSON.encode(actionProperties === null ? {} : actionProperties),
				object_properties: com.carrot.adobe.serialization.json.JSON.encode(objectProperties === null ? {} : objectProperties)
			}
			if(objectInstanceId !== null) {
				params.object_instance_id = objectInstanceId;
			}
			return postSignedRequest("/me/actions.json", params, bitmapData, callback);
		}

		/**
		 * Inform Carrot about a purchase of premium currency for metrics tracking.

		 * @param amount    The amount of real money spent.
		 * @param currency  The type of real money spent (eg. USD).
		 * @param callback  A function which will be called upon completion of the high score post.
		 */
		public function postPremiumCurrencyPurchase(amount:Number, currency:String, callback:Function = null):Boolean {
			var params:Object = {
				amount: amount,
				currency: currency
			};
			return makeSignedRequest(_metricsHostname, "/purchase.json", URLRequestMethod.POST, params, null, callback);
		}

		/* Private methods */

		private function performServicesDiscovery():Boolean {
			var params:Object = {
				game_id: _appId,
				_method: "GET"
			};
			addCommonPayloadFields(params);

			var loader:MultipartURLLoader = new MultipartURLLoader();
			for(var k:String in params) {
				loader.addVariable(k, params[k]);
			}

			loader.addEventListener(Event.COMPLETE, function(event:Event):void {
				var services:Object = com.carrot.adobe.serialization.json.JSON.decode(event.target.loader.data.toString());
				_postHostname = services.post;
				_authHostname = services.auth;
				_metricsHostname = services.metrics;
			});

			try {
				loader.load("http://" + _servicesDiscoveryHost + "/services.json");
				return true;
			}
			catch(error:Error) {
				trace(error);
			}

			return false;
		}

		private function addCommonPayloadFields(urlParams:Object):void {
			urlParams["sdk_type"] = "flash";
			urlParams["sdk_version"] = SDKVersion;
			urlParams["sdk_platform"] = Capabilities.os.replace(" ", "_").toLowerCase();
			urlParams["app_version"] = _appVersion;
		}

		private function postSignedRequest(endpoint:String, queryParams:Object, bitmapData:BitmapData, callback:Function, httpStatusCallback:Boolean = false):Boolean {
			var timestamp:Date = new Date();

			var urlParams:Object = {
				request_date: Math.round(timestamp.getTime() / 1000),
				request_id: new Uuid().toString()
			};

			for(var k:String in queryParams) {
				urlParams[k] = queryParams[k];
			}
			return makeSignedRequest(_postHostname, endpoint, URLRequestMethod.POST, urlParams, bitmapData, callback, httpStatusCallback);
		}

		private function makeSignedRequest(hostname:String, endpoint:String, method:String, queryParams:Object, bitmapData:BitmapData, callback:Function, httpStatusCallback:Boolean = false):Boolean {
			var urlParams:Object = {
				api_key: _udid,
				game_id: _appId
			};

			for(var k:String in queryParams) {
				urlParams[k] = queryParams[k];
			}

			addCommonPayloadFields(urlParams);

			var pngBytes:ByteArray = null;
			if(bitmapData !== null) {
				pngBytes = PNGEncoder2.encode(bitmapData);
				var object_properties:Object = com.carrot.adobe.serialization.json.JSON.decode(urlParams.object_properties);
				object_properties.image_sha = SHA256.hashBytes(pngBytes);
				urlParams.object_properties = com.carrot.adobe.serialization.json.JSON.encode(object_properties);
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

			var signString:String = method + "\n" + hostname + "\n" + endpoint + "\n" + urlString;
			var digest:String = HMAC.hash(_appSecret, signString, SHA256);
			var hashBytes:ByteArray = new ByteArray();
			for(var i:uint = 0; i < digest.length; i += 2)
				hashBytes.writeByte(parseInt(digest.charAt(i) + digest.charAt(i + 1), 16));
			urlParams.sig = Base64.encode(hashBytes);

			return httpRequest(hostname, method, endpoint, urlParams, pngBytes, callback, httpStatusCallback);
		}

		private function httpRequest(hostname:String, method:String, endpoint:String, urlParams:Object, pngBytes:ByteArray, callback:Function, httpStatusCallback:Boolean = false):Boolean {
			if(hostname === null) {
				return false;
			}

			var loader:MultipartURLLoader = new MultipartURLLoader();
			if(urlParams !== null) {
				for(var k:String in urlParams) {
					loader.addVariable(k, urlParams[k]);
				}
			}

			if(pngBytes !== null) {
				loader.addFile(pngBytes, "attachment.png", "image_bytes", "application/octet-stream")
			}

			if(callback !== null) {
				if(httpStatusCallback) {
					loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, callback);
				}
				else {
					loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(event:HTTPStatusEvent):void {
						var apiCallStatus:String = UNKNOWN;
						switch(event.status) {
							case 200:
							case 201: _status = AUTHORIZED; apiCallStatus = OK; break;
							case 401: apiCallStatus = _status = READ_ONLY; break;
							case 403: apiCallStatus = _status = BAD_SECRET; break;
							case 405: apiCallStatus = _status = NOT_AUTHORIZED; break;
						}
						if(method === URLRequestMethod.POST && callback !== null) {
							callback(apiCallStatus);
						}
					});
				}
			}

			try {
				loader.load("https://" + hostname + endpoint);
				return true;
			}
			catch(error:Error) {
				trace(error);
			}
			return false;
		}

		private var _udid:String;
		private var _appId:String;
		private var _appSecret:String;
		private var _status:String;
		private var _appVersion:String;

		private var _postHostname:String;
		private var _authHostname:String;
		private var _metricsHostname:String;

		private static const _servicesDiscoveryHost:String = "services.gocarrot.com";
	}
}
