/* Carrot -- Copyright (C) 2012 Carrot Inc.
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

		public function Carrot(appId:String, appSecret:String, udid:String) {
			_appId = appId;
			_appSecret = appSecret;
			_hostname = "gocarrot.com";
			_udid = udid;
		}

		public function validateUser(callback:Function = null):Boolean {
			var params:Object = {
				id: _udid
			}
			return httpRequest(URLRequestMethod.GET, "/games/" + _appId + "/users.json", params, function(event:HTTPStatusEvent):void {
				switch(event.status) {
					case 200: _status = AUTHORIZED; break;
					case 401: _status = READ_ONLY; break;
					case 403: _status = NOT_AUTHORIZED; break;
					case 404: _status = NOT_CREATED; break;
					default: _status = UNKNOWN; break;
				}
				if(callback != null) {
					callback(_status);
				}
			});
		}

		public function createUser(accessToken:String, callback:Function = null):Boolean {
			var params:Object = {
				access_token: accessToken,
				api_key: _udid
			}
			return httpRequest(URLRequestMethod.POST, "/games/" + _appId + "/users/users.json", params, function(event:HTTPStatusEvent):void {
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

		public function postAchievement(achievementId:String, callback:Function = null):Boolean {
			return postSignedRequest("/me/achievements.json", {achievement_id: achievementId}, callback);
		}

		public function postHighScore(score:uint, leaderboardId:String = "", callback:Function = null):Boolean {
			return postSignedRequest("/me/scores.json", {value: score, leaderboard_id: leaderboardId}, callback);
		}

		public function postAction(actionId:String, objectInstanceId:String, actionProperties:Object = null, objectProperties:Object = null, callback:Function = null):Boolean {
			var params:Object = {
				action_id: actionId,
				action_properties: JSON.encode(actionProperties === null ? {} : actionProperties),
				object_properties: JSON.encode(objectProperties === null ? {} : objectProperties)
			}
			if(objectInstanceId != null) {
				params.object_instance_id = objectInstanceId;
			}
			return postSignedRequest("/me/actions.json", params, callback);
		}

		private function postSignedRequest(endpoint:String, queryParams:Object, callback:Function):Boolean {
			var timestamp:Date = new Date();

			var urlParams:Object = {
				api_key: _udid,
				game_id: _appId,
				request_date: Math.round(timestamp.getTime() / 1000),
				request_id: UIDUtil.createUID()
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

			var signString:String = "POST\n" + _hostname + "\n" + endpoint + "\n" + urlString;
			var digest:String = HMAC.hash(_appSecret, signString, SHA256);
			var hashBytes:ByteArray = new ByteArray();
			for(var i:uint = 0; i < digest.length; i += 2)
				hashBytes.writeByte(parseInt(digest.charAt(i) + digest.charAt(i + 1), 16));
			var encoder:Base64Encoder = new Base64Encoder();
			encoder.encodeBytes(hashBytes);
			urlParams.sig = encoder.toString();

			return httpRequest(URLRequestMethod.POST, endpoint, urlParams, getCallbackHandlerFunction(callback));
		}

		private function httpRequest(method:String, endpoint:String, urlParams:Object, callback:Function):Boolean {
			var request:URLRequest = new URLRequest("https://" + _hostname + endpoint);
			request.method = method;
			if(urlParams != null) {
				var urlVars:URLVariables = new URLVariables();
				for(var k:String in urlParams) {
					urlVars[k] = urlParams[k];
				}
				request.data = urlVars;
			}

			var loader:URLLoader = new URLLoader();
			if(callback != null) {
				loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, callback);
			}

			try {
				loader.load(request);
				return true;
			}
			catch(error:Error) {
				trace(error);
			}
			return false;
		}

		private function getCallbackHandlerFunction(callback:Function):Function {
			return function(event:HTTPStatusEvent):void {
				switch(event.status) {
					case 200:
					case 201: _status = OK; break;
					case 401: _status = READ_ONLY; break;
					case 403: _status = BAD_SECRET; break;
					case 404: _status = NOT_AUTHORIZED; break;
					default: _status = UNKNOWN; break;
				}
				if(callback != null) {
					callback(_status);
				}
			};
		}

		private var _udid:String;
		private var _appId:String;
		private var _hostname:String;
		private var _appSecret:String;
		private var _status:String;
	}
}
