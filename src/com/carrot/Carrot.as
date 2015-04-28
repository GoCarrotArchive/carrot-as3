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
	import flash.external.ExternalInterface;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.net.URLVariables;
	import flash.net.URLLoader;
	import flash.events.Event;
	import flash.utils.ByteArray;
	import flash.display.BitmapData;
	import flash.system.Capabilities;
	import flash.events.HTTPStatusEvent;
	import flash.utils.Dictionary;
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

		public static const SDKVersion:String = "1.3";

		private static const JS_SDK_LOAD:XML =
			<script>
				<![CDATA[
					function(){if(!window.teak){window.teak=window.teak||[];window.teak.methods=["init","setUdid","setSWFObjectID","internal_directFeedPost","internal_directRequest","identify","postAction","postAchievement","postHighScore","canMakeFeedPost","popupFeedPost","reportNotificationClick","reportFeedClick","sendRequest","acceptRequest"];window.teak.factory=function(e){return function(){var t=Array.prototype.slice.call(arguments);t.unshift(e);window.teak.push(t);return window.teak}};for(var e=0;e<window.teak.methods.length;e++){var t=window.teak.methods[e];window.teak[t]=window.teak.factory(t)}var n=document.createElement("script");n.type="text/javascript";n.async=true;n.src="//d2h7sc2qwu171k.cloudfront.net/teak.min.js";var r=document.getElementsByTagName("script")[0];r.parentNode.insertBefore(n,r)}}
				]]>
			</script>;

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
			_openUICalls = new Dictionary();

			// Defaults
			_postHostname = "gocarrot.com";
			_metricsHostname = "parsnip.gocarrot.com";
			_authHostname = "gocarrot.com";

			// GoViral Facebook ANE
			try {
				_gv = flash.utils.getDefinitionByName("com.milkmangames.nativeextensions.GoViral") as Class;
				_gvFacebookDispatcher = flash.utils.getDefinitionByName("com.milkmangames.nativeextensions.GVFacebookDispatcher") as Class;
				_gvFacebookEvent  = flash.utils.getDefinitionByName("com.milkmangames.nativeextensions.events.GVFacebookEvent") as Class;
			}
			catch(error:Error) {}

			if(!ExternalInterface.available && (_gv === null || _gvFacebookDispatcher === null || _gvFacebookEvent === null)) {
				trace("ExternalInterface not available and GoViral ANE not found.");
			}

			// Perform services discovery
			if(!performServicesDiscovery()) {
				trace("Could not perform services discovery. Carrot is offline.");
			}

			try {
				if(ExternalInterface.available) {
					_httpStatusEvent = HTTPStatusEvent.HTTP_STATUS;
					ExternalInterface.addCallback("teakUiCallback", handleUI);
					ExternalInterface.call(JS_SDK_LOAD);
					ExternalInterface.call("window.teak.init", _appId, _appSecret);
					ExternalInterface.call("window.teak.setUdid", _udid);
					ExternalInterface.call("window.teak.setSWFObjectID", ExternalInterface.objectID);
				}
				else {
					_httpStatusEvent = HTTPStatusEvent.HTTP_RESPONSE_STATUS;
				}
			} catch(error:Error) {
				_httpStatusEvent = HTTPStatusEvent.HTTP_RESPONSE_STATUS;
			}
		}

		private function handleUI(result:String, callbackId:String):void {
			var decodedResult:Object = result ? com.carrot.adobe.serialization.json.JSON.decode(result) : {carrotResponse:null, fbResponse:null};
			var uiCallback:Function = _openUICalls[callbackId];
			if(uiCallback !== null) {
				uiCallback(decodedResult.carrotResponse, decodedResult.fbResponse);
			}
			delete _openUICalls[callbackId];
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
		 * Post an achievement.
		 *
		 * All achievements are defined under the 'earn an achievement' story in your game's
		 * settings. This call cannot be used to post any other stories.
		 *
		 * @param achievementId The object instance identifier of the achievement to be posted.
		 * @param callback      Optional callback.
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
		 * @param score     The user's score. Yes, it's an integer, and yes, you only get one per user per game.
		 *                  I'm sorry, that's just how Facebook does it...
		 * @param callback  Optional callback.
		 */
		public function postHighScore(score:uint, callback:Function = null):Boolean {
			return postSignedRequest("/me/scores.json", {value: score}, null, callback);
		}

		/**
		 * Post a custom open graph action.
		 *
		 * This is the primary work horse of Teak. This method is used to post all custom actions,
  		 * either as explicitly shared, implicitly shared, with a user message, with custom variables...
		 *
		 * @param actionId          The identifier for the action, e.g. 'complete'. Refer to the 'Get Code' feature of the story you're implementing to get the correct identifier.
		 * @param objectInstanceId  The identifier for the specific instance that should be posted. This is the value next to the '#' above every object in a story list.
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

		private function generateJSCallback(callback:Function):String {
			var callbackId:String = null;
			if(callback != null) {
				callbackId = new Uuid().toString();
				_openUICalls[callbackId] = callback;
			}
			return callbackId;
		}


		/**
		 * Post a feed post to the user's wall
		 *
		 * This method is used to share arbitrary non-opengraph content to the user's wall.
		 * Depending on CMS configuration this method may cause a Facebook dialog to appear, or it may share
		 * seamlessly.
		 *
		 * @param objectInstanceId  The identifier for the specific instance that should be posted. This is the value next to the '#' above every object in the list of feed posts.
		 * @param objectProperties  Properties which can be inserted into the title, description, or link of the post through Custom Variables specified in the CMS.
		 * @param callback          A function which will be called upon completion of the post. It takes two parameters, the first details the content of the post,
		 *													the second will contain a 'post_id' value if the post was made, or no post_id value if the user cancelled making the post.
		 */
		public function popupFeedPost(objectInstanceId:String, objectProperties:Object, callback:Function = null):Boolean {
			try {
				if(ExternalInterface.available) {
					ExternalInterface.call("window.teak.popupFeedPost", objectInstanceId, objectProperties, generateJSCallback(callback));
					return true;
				}
			} catch(error:Error) {}

			if(_gv !== null) {
				if(objectInstanceId === null) {
					throw new Error("objectInstanceId may not be null");
				}

				var params:Object = {
					object_instance_id: objectInstanceId,
					object_properties: com.carrot.adobe.serialization.json.JSON.encode(objectProperties === null ? {} : objectProperties)
				};

				try {
					postSignedRequest("/me/feed_post.json", params, null, function(event:HTTPStatusEvent):void {
						event.target.addEventListener(Event.COMPLETE, function(event:Event):void {
							var data:Object = com.carrot.adobe.serialization.json.JSON.decode(event.target.loader.data);

							if(data.autoshare) {
								var dispatcher:Object = _gv["goViral"]["facebookGraphRequest"].call(_gv["goViral"],
									"me/feed", "POST", data.fb_data, "publish_actions");
								dispatcher["addRequestListener"].call(dispatcher, function(event:Event):void {
									if(event.type === _gvFacebookEvent["FB_REQUEST_RESPONSE"] && event["data"]["postId"]) {
										httpRequest("parsnip.gocarrot.com", URLRequestMethod.POST, "/feed_dialog_post", {
											platform_id: data.post_id,
											placement_id: event["data"]["postId"]
										}, null, null);
									}
									else if(data.dialog_fallback) {
										nativePopupFeedPost(data, callback);
									}
								});
							}
							else {
								nativePopupFeedPost(data, callback);
							}
						});
					}, true);
					return true;
				} catch(error:Error) {}
			}
			return false;
		}

		public function sendRequest(requestId:String, options:Object, callback:Function = null):Boolean {
			try{
				if(ExternalInterface.available) {
					ExternalInterface.call("window.teak.sendRequest", requestId, options, generateJSCallback(callback));
					return true;
				}
			} catch(error:Error) {}
			return false;
		}

		/**
		 * Tell Carrot to track an arbitrary event.
		 *
		 * @param evenType    The type of event you are tracking.
		 * @param eventValue   The value of the event you are tracking.
		 * @param eventContext Optional additional context for the event.
		 */
		public function trackEvent(evenType:String, eventValue:String, eventContext:String = ""):Boolean {
			if(evenType === null) {
				throw new Error("evenType must not be null");
			}
			if(eventValue === null) {
				throw new Error("eventValue must not be null");
			}

			var params:Object = {
				action_type: evenType,
				object_type: eventValue,
				object_instance_id: eventContext
			}

			return postSignedRequest("/me/events", params, null, null);
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

CONFIG::AirNative {
		public function reportNativeInvokeEvent(arguments:Array):void {
			var args:Array = arguments[0].split("#")[1].split("&");
			for(var i:uint = 0; i < args.length; i++) {
				var arg:Array = args[i].split("=");
				if(arg[0] === "target_url") {
					var params:Array = unescape(arg[1]).split("?")[1].split("&");
					for(var j:uint = 0; j < params.length; j++) {
						var param:Array = params[j].split("=");
						if(param[0] === "teak_post_id") {
							httpRequest("posts.gocarrot.com", URLRequestMethod.POST, "/" + param[1] + "/clicks", {
								clicking_user_id: _udid,
								no_status_code: true
							}, null, null);
							break;
						}
					}
					break;
				}
			}
		}
}
		/* Private methods */

		private function nativePopupFeedPost(data:Object, callback:Function = null):void {
			if(_gv !== null) {
				try {
					if(data.code === 200) {
						var dispatcher:Object = _gv["goViral"]["showFacebookShareDialog"].call(_gv["goViral"],
							data.fb_data.name,
							data.fb_data.caption,
							data.fb_data.description,
							data.fb_data.link,
							data.fb_data.picture,
							data.fb_data.ref === null ? null : {ref: data.fb_data.ref});

						dispatcher["addDialogListener"].call(dispatcher, function(event:Event):void {
							if(event.type === _gvFacebookEvent["FB_DIALOG_FINISHED"]) {
								httpRequest("parsnip.gocarrot.com", URLRequestMethod.POST, "/feed_dialog_post", {
									platform_id: data.post_id,
									placement_id: event["data"]["postId"]
								}, null, null);
							}
							if(callback !== null) callback(data, event["data"]);
						});
					}
					else {
						if(callback !== null) callback(data);
					}
				} catch(error:Error) {
					trace("GoViral::showFacebookShareDialog() error: " + error);
				}
			}
		}

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
				loader.load("https://" + _servicesDiscoveryHost + "/services.json");
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

CONFIG::NotAirNative {
			if(bitmapData !== null) {
				pngBytes = PNGEncoder2.encode(bitmapData);
				var object_properties:Object = com.carrot.adobe.serialization.json.JSON.decode(urlParams.object_properties);
				object_properties.image_sha = SHA256.hashBytes(pngBytes);
				urlParams.object_properties = com.carrot.adobe.serialization.json.JSON.encode(object_properties);
			}
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
			var httpStatus:int = 0;
			var internalHttpStatusCallback:Function = function():void {
				var apiCallStatus:String = _status;
				if(hostname !== _metricsHostname) {
					switch(httpStatus) {
						case 200:
						case 201: _status = AUTHORIZED; apiCallStatus = OK; break;
						case 401: apiCallStatus = _status = READ_ONLY; break;
						case 403: apiCallStatus = _status = BAD_SECRET; break;
						case 405: apiCallStatus = _status = NOT_AUTHORIZED; break;
					}
				}
				if(method === URLRequestMethod.POST && callback !== null && !httpStatusCallback) {
					callback(apiCallStatus);
				}
			}
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
					loader.addEventListener(_httpStatusEvent, callback);
				}
				else {
					loader.addEventListener(_httpStatusEvent, function(event:HTTPStatusEvent):void {
						httpStatus = event.status;
					});
				}
			}

			loader.addEventListener(Event.COMPLETE, function(event:Event):void {
				var data:Object = com.carrot.adobe.serialization.json.JSON.decode(loader.loader.data);
				if(data.cascade && data.cascade.method == "feedpost") {
					if(ExternalInterface.available) {
						try {
							ExternalInterface.call("window.teak.internal_directFeedPost", data.cascade.arguments, generateJSCallback(callback));
						} catch(error:Error) {}
					}
					else if(_gv !== null) {
						nativePopupFeedPost(data.cascade.arguments, callback);
					}
				} else if(data.cascade && data.cascade.method == "request") {
					if(ExternalInterface.available) {
						try {
							ExternalInterface.call("window.teak.internal_directRequest", data.cascade.arguments, generateJSCallback(callback));
						} catch(error:Error) {}
					}
				} else if(data.cascade && data.cascade.method == "sendRequest") {
					sendRequest(data.cascade.arguments.request_id, data.cascade.arguments.object_properties);
				} else {
					internalHttpStatusCallback();
				}
			});

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

		private var _openUICalls:Dictionary;

		private var _gv:Class;
		private var _gvFacebookDispatcher:Class;
		private var _gvFacebookEvent:Class;

		private var _httpStatusEvent:String;

		private static const _servicesDiscoveryHost:String = "services.gocarrot.com";
	}
}
