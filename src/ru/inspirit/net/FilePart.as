package ru.inspirit.net
{
	import flash.utils.ByteArray;
	internal class FilePart
	{
		public var fileContent:ByteArray;
		public var fileName:String;
		public var dataField:String;
		public var contentType:String;

		public function FilePart(fileContent:ByteArray, fileName:String, dataField:String = 'Filedata', contentType:String = 'application/octet-stream')
		{
			this.fileContent = fileContent;
			this.fileName = fileName;
			this.dataField = dataField;
			this.contentType = contentType;
		}

		public function dispose():void
		{
			fileContent = null;
			fileName = null;
			dataField = null;
			contentType = null;
		}
	}
}
