jQuery(function () {
    var $ = jQuery;
    var $list = $('#file_list');
    var isUploaded = false;
    var hasUploaded = false;
    var uploadNum = 0;

    var uploader = WebUploader.create({
        swf: 'Uploader.swf',
        method: 'POST',
        server: 'upload.html',//'/files?'+ new Date().getTime(),
        pick: {
            id: '#file_picker',
            multiple: true
        },
        fileNumLimit: 50,
        fileVal: "newfile",
        accept: {
            extensions: 'mp3',
        }
    });

    uploader.on('error', function(type) {
        if (type === 'Q_TYPE_DENIED') {
            alert('Only mp3 files supported.');
        }
        else if (type === 'Q_EXCEED_NUM_LIMIT') {
            alert('The number of files added exceeds 50');
        }
        else {
            console.log(type);
        }
    });

    uploader.on('beforeFileQueued', function(file) {
        checkUploadStatus();
        if (!isUploaded) {
            $("#no_data_tip").hide();
            $("#desc").html('Device connected, you can upload now.Tips: only mp3 supported');
            return true;
        }
        else {
            alert('The file is being uploaded and can not add a new file temporarily');
            return false;
        }
    });

    uploader.on('fileQueued', function(file) {
        uploadNum ++;
        $list.append(
            '<tr class="selected_item" id="' + file.id + '">' +
                '<td class="title">' +
                    '<span>' + file.name + '</span>' +
                '</td>' +
                '<td class="size">' +
                    WebUploader.Base.formatSize(file.size) +
                '</td>' +
                '<td class="progressbar">' +
                    '<div class="track">' +
                        '<div id="progress_' + file.id + '" class="progress" />' +
                    '</div>' +
                '</td>' +
                '<td class="cancel">' +
                    '<div>' +
                        '<img id="cancel_' + file.id + '" class="item_cancel" src="images/upload_cancel.png" />' +
                        '<span id="done_' + file.id + '" class="item_done">success</span>' +
                    '</div>' +
                '</td>' +
            '</tr>');
        $('#cancel_' + file.id).bind('click', file, function(e) {
            if (isUploaded) {
                alert('Uploading or waiting for uploading can not be deleted');
            }
            else {
                uploader.removeFile(e.data);
            }
        });

        refreshUploadButton();
    });

    uploader.on('fileDequeued', function(file) {
        $('#' + file.id).remove();
        uploadNum --;
        refreshUploadButton();
        if (uploadNum == 0 && !hasUploaded) {
            $("#no_data_tip").show();
        }
    });

    uploader.on('uploadProgress', function(file, percentage) {
        $('#progress_' + file.id).css('width', parseInt(percentage * 100) + '%');
    });

    uploader.on('uploadSuccess', function(file, response) {
        $("#cancel_" + file.id).hide();
        $("#done_" + file.id).show();
        $("#done_" + file.id).text('Upload successfully');
        hasUploaded = true;
        uploadNum --;
        if (uploadNum == 0) {
            $("#desc").html('Upload successfully');
        }
    });

    uploader.on('uploadError', function(file, reason) {
        $("#cancel_" + file.id).hide();
        $("#done_" + file.id).show();
        $("#done_" + file.id).text('Upload failed');
    });

    $('#upload_button').bind('click', function() {
        isUploaded = true;
        uploader.upload();
        refreshUploadButton();
    });

    function refreshUploadButton() {
        if (!isUploaded && $('#file_list > tbody > tr').children().length > 0) {
            if (uploadNum == 0) {
                $('#upload_button').hide();
                $('#upload_button_disabled').show();
            } else {
                $('#upload_button').show();
                $('#upload_button_disabled').hide();   
            }
        }
        else {
            $('#upload_button').hide();
            $('#upload_button_disabled').show();
        }
    }

    function checkUploadStatus() {
        if (uploadNum == 0) {
            isUploaded = false;
        }
    }
});