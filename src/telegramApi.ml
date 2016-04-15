open TelegramUtil
open Yojson.Safe

exception ApiException of string

module User = struct
  type user = {
    id         : int;
    first_name : string;
    last_name  : string option;
    username   : string option
  }

  let create ~id ~first_name ?(last_name=None) ?(username=None) () =
    {id; first_name; last_name; username}

  let read obj =
    let id = the_int @@ get_field "id" obj in
    let first_name = the_string @@ get_field "first_name" obj in
    let last_name = the_string <$> get_opt_field "last_name" obj in
    let username = the_string <$> get_opt_field "last_name" obj in
    create ~id ~first_name ~last_name ~username ()
end

module Chat = struct
  type chat_type = Private | Group | Supergroup | Channel

  let read_type = function
    | "private" -> Private
    | "group" -> Group
    | "supergroup" -> Supergroup
    | "channel" -> Channel
    | _ -> raise (ApiException "Unknown chat type!")

  type chat = {
    id         : int;
    chat_type  : chat_type;
    title      : string option;
    username   : string option;
    first_name : string option;
    last_name  : string option
  }

  let create ~id ~chat_type ?(title=None) ?(username=None) ?(first_name=None) ?(last_name=None) () =
    {id; chat_type; title; username; first_name; last_name}

  let read obj =
    let id = the_int @@ get_field "id" obj in
    let chat_type = read_type @@ the_string @@ get_field "type" obj in
    let title = the_string <$> get_opt_field "title" obj in
    let username = the_string <$> get_opt_field "username" obj in
    let first_name = the_string <$> get_opt_field "first_name" obj in
    let last_name = the_string <$> get_opt_field "last_name" obj in
    create ~id ~chat_type ~title ~username ~first_name ~last_name ()
end

module MessageEntity = struct
  type entity_type =
    | Mention
    | Hashtag
    | BotCommand
    | Url
    | Email
    | Bold
    | Italic
    | Code
    | Pre
    | TextLink of string

  let entity_type_of_string url = function
    | "mention" -> Mention
    | "hashtag" -> Hashtag
    | "bot_command" -> BotCommand
    | "url" -> Url
    | "email" -> Email
    | "bold" -> Bold
    | "italic" -> Italic
    | "code" -> Code
    | "pre" -> Pre
    | "text_link" -> begin match url with
        | Some url -> TextLink url
        | None -> raise @@ ApiException "MessageEntity of type 'text_link' missing url"
      end
    | _ -> raise @@ ApiException "Unrecognized type of MessageEntity encountered"

  type message_entity = {
    entity_type : entity_type;
    offset      : int;
    length      : int
  }

  let create ~entity_type ~offset ~length () =
    {entity_type; offset; length}

  let read obj =
    let url = the_string <$> get_opt_field "url" obj in
    let entity_type = entity_type_of_string url @@ the_string @@ get_field "type" obj in
    let offset = the_int @@ get_field "offset" obj in
    let length = the_int @@ get_field "length" obj in
    create ~entity_type ~offset ~length ()
end

module InputFile = struct
  open Lwt

  let load (file:string) =
    let open Lwt_io in
    with_file ~mode:input file read

  let multipart_body fields (name, file, mime) boundary' =
    let boundary = "--" ^ boundary' in
    let ending = boundary ^ "--"
    and break = "\r\n" in
    load file >>= fun file_bytes ->
    let field_bodies = List.map (fun (name, value) ->
        boundary ^ break
        ^ "Content-Disposition: form-data; name=\"" ^ name ^ "\"" ^ break ^ break
        ^ value ^ break) fields |> fun strs -> List.fold_right (^) strs "" in
    let file_body =
      boundary ^ break
      ^ "Content-Disposition: form-data; name=\"" ^ name ^ "\"; filename=\"" ^ file ^ "\"" ^ break
      ^ "Content-Type: " ^ mime ^ break ^ break
      ^ file_bytes ^ break in
    return @@ field_bodies ^ file_body ^ ending
end

module KeyboardButton = struct
  type keyboard_button = {
    text             : string;
    request_contact  : bool option;
    request_location : bool option
  }

  let create ~text ?(request_contact=None) ?(request_location=None) () =
    {text; request_contact; request_location}

  let prepare button =
    `Assoc (["text", `String button.text] +? ("request_contact", this_bool <$> button.request_contact)
                                          +? ("request_location", this_bool <$> button.request_location))
end

module InlineKeyboardButton = struct
  type inline_keyboard_button = {
    text                : string;
    url                 : string option;
    callback_data       : string option;
    switch_inline_query : string option
  }

  let create ~text ?(url=None) ?(callback_data=None) ?(switch_inline_query=None) () =
    {text; url; callback_data; switch_inline_query}

  let prepare button =
    `Assoc (["text", `String button.text] +? ("url", this_string <$> button.url)
                                          +? ("callback_data", this_string <$> button.callback_data)
                                          +? ("switch_inline_query", this_string <$> button.switch_inline_query))
end

module ReplyMarkup = struct
  type reply_keyboard_markup = {
    keyboard          : KeyboardButton.keyboard_button list list;
    resize_keyboard   : bool option;
    one_time_keyboard : bool option;
    selective         : bool option
  }

  type reply_keyboard_hide = {
    selective : bool option
  }

  type inline_keyboard_markup = {
    inline_keyboard : InlineKeyboardButton.inline_keyboard_button list list
  }

  type force_reply = {
    selective : bool option
  }

  type reply_markup =
    | ReplyKeyboardMarkup of reply_keyboard_markup
    | InlineKeyboardMarkup of inline_keyboard_markup
    | ReplyKeyboardHide of reply_keyboard_hide
    | ForceReply of force_reply

  let create_reply_keyboard_markup ~keyboard ?(resize_keyboard = None) ?(one_time_keyboard = None) ?(selective = None) () =
    ReplyKeyboardMarkup {keyboard; resize_keyboard; one_time_keyboard; selective}

  let create_inline_keyboard_markup ~inline_keyboard () =
    InlineKeyboardMarkup {inline_keyboard}

  let create_reply_keyboard_hide ?(selective = None) () =
    ReplyKeyboardHide {selective}

  let create_force_reply ?(selective = None) () =
    ForceReply {selective}

  let prepare = function
    | ReplyKeyboardMarkup {keyboard; resize_keyboard; one_time_keyboard; selective} ->
      let keyboard = List.map (fun row -> `List (List.map (fun key -> KeyboardButton.prepare key) row)) keyboard in
      `Assoc ([("keyboard", `List keyboard)] +? ("resize_keyboard", this_bool <$> resize_keyboard)
                                             +? ("one_time_keyboard", this_bool <$> one_time_keyboard)
                                             +? ("selective", this_bool <$> selective))
    | InlineKeyboardMarkup {inline_keyboard} ->
      let keyboard = List.map (fun row -> `List (List.map (fun key -> InlineKeyboardButton.prepare key) row)) inline_keyboard in
      `Assoc ["inline_keyboard", `List keyboard]
    | ReplyKeyboardHide {selective} ->
      `Assoc ([("hide", `Bool true)] +? ("selective", this_bool <$> selective))
    | ForceReply {selective} ->
      `Assoc ([("force_reply", `Bool true)] +? ("selective", this_bool <$> selective))
end

module PhotoSize = struct
  type photo_size = {
    file_id   : string;
    width     : int;
    height    : int;
    file_size : int option
  }

  let create ~file_id ~width ~height ?(file_size = None) () =
    {file_id; width; height; file_size}

  let read obj =
    let file_id = the_string @@ get_field "file_id" obj in
    let width = the_int @@ get_field "width" obj in
    let height = the_int @@ get_field "height" obj in
    let file_size = the_int <$> get_opt_field "file_size" obj in
    create ~file_id ~width ~height ~file_size ()

  module Out = struct
    type photo_size = {
      chat_id             : int;
      photo               : string;
      caption             : string option;
      reply_to_message_id : int option;
      reply_markup        : ReplyMarkup.reply_markup option
    }

    let create ~chat_id ~photo ?(caption = None) ?(reply_to = None) ?(reply_markup = None) () =
      {chat_id; photo; caption; reply_to_message_id = reply_to; reply_markup}

    let prepare = function
    | {chat_id; photo; caption; reply_to_message_id; reply_markup} ->
      let json = `Assoc ([("chat_id", `Int chat_id);
                          ("photo", `String photo)] +? ("caption", this_string <$> caption)
                                                    +? ("reply_to_message_id", this_int <$> reply_to_message_id)
                                                    +? ("reply_markup", ReplyMarkup.prepare <$> reply_markup))in
      Yojson.Safe.to_string json

    let prepare_multipart = function
      | {chat_id; photo; caption; reply_to_message_id; reply_markup} ->
        let fields = ([("chat_id", string_of_int chat_id)] +? ("caption", caption)
                                                           +? ("reply_to_message_id", string_of_int <$> reply_to_message_id)
                                                           +? ("reply_markup", Yojson.Safe.to_string <$> (ReplyMarkup.prepare <$> reply_markup))) in
        let open Batteries.String in
        let mime =
          if ends_with photo ".jpg" || ends_with photo ".jpeg" then "image/jpeg" else
          if ends_with photo ".png" then "image/png" else
          if ends_with photo ".gif" then "image/gif" else "text/plain" in
        InputFile.multipart_body fields ("photo", photo, mime)
  end
end

module Audio = struct
  type audio = {
    file_id   : string;
    duration  : int;
    performer : string option;
    title     : string option;
    mime_type : string option;
    file_size : int option
  }

  let create ~file_id ~duration ?(performer = None) ?(title = None) ?(mime_type = None) ?(file_size = None) () =
    {file_id; duration; performer; title; mime_type; file_size}

  let read obj =
    let file_id = the_string @@ get_field "file_id" obj in
    let duration = the_int @@ get_field "duration" obj in
    let performer = the_string <$> get_opt_field "performer" obj in
    let title = the_string <$> get_opt_field "title" obj in
    let mime_type = the_string <$> get_opt_field "mime_type" obj in
    let file_size = the_int <$> get_opt_field "file_size" obj in
    create ~file_id ~duration ~performer ~title ~mime_type ~file_size ()

  module Out = struct
    type audio = {
      chat_id             : int;
      audio               : string;
      duration            : int option;
      performer           : string;
      title               : string;
      reply_to_message_id : int option;
      reply_markup        : ReplyMarkup.reply_markup option
    }

    let create ~chat_id ~audio ?(duration = None) ~performer ~title ?(reply_to = None) ?(reply_markup = None) () =
      {chat_id; audio; duration; performer; title; reply_to_message_id = reply_to; reply_markup}

    let prepare = function
    | {chat_id; audio; duration; performer; title; reply_to_message_id; reply_markup} ->
      let json = `Assoc ([("chat_id", `Int chat_id);
                          ("audio", `String audio);
                          ("performer", `String performer);
                          ("title", `String title)] +? ("duration", this_int <$> duration)
                                                    +? ("reply_to_message_id", this_int <$> reply_to_message_id)) in
      Yojson.Safe.to_string json

    let prepare_multipart = function
      | {chat_id; audio; duration; performer; title; reply_to_message_id} ->
        let fields = [("chat_id", string_of_int chat_id);
                      ("performer", performer);
                      ("title", title)] +? ("duration", string_of_int <$> duration)
                                        +? ("reply_to_message_id", string_of_int <$> reply_to_message_id) in
        InputFile.multipart_body fields ("audio", audio, "audio/mpeg")
  end
end

module Document = struct
  type document = {
    file_id   : string;
    thumb     : PhotoSize.photo_size option;
    file_name : string option;
    mime_type : string option;
    file_size : int option
  }

  let create ~file_id ?(thumb = None) ?(file_name = None) ?(mime_type = None) ?(file_size = None) () =
    {file_id; thumb; file_name; mime_type; file_size}

  let read obj =
    let file_id = the_string @@ get_field "file_id" obj in
    let thumb = PhotoSize.read <$> get_opt_field "thumb" obj in
    let file_name = the_string <$> get_opt_field "file_name" obj in
    let mime_type = the_string <$> get_opt_field "mime_type" obj in
    let file_size = the_int <$> get_opt_field "file_size" obj in
    create ~file_id ~thumb ~file_name ~mime_type ~file_size ()

  module Out = struct
    type document = {
      chat_id             : int;
      document            : string;
      reply_to_message_id : int option;
      reply_markup        : ReplyMarkup.reply_markup option
    }

    let create ~chat_id ~document ?(reply_to = None) ?(reply_markup = None) () =
      {chat_id; document; reply_to_message_id = reply_to; reply_markup}

    let prepare = function
    | {chat_id; document; reply_to_message_id; reply_markup} ->
      let json = `Assoc ([("chat_id", `Int chat_id);
                          ("document", `String document)] +? ("reply_to_message_id", this_int <$> reply_to_message_id)
                                                          +? ("reply_markup", ReplyMarkup.prepare <$> reply_markup)) in
      Yojson.Safe.to_string json

    let prepare_multipart = function
      | {chat_id; document; reply_to_message_id; reply_markup} ->
        let fields = [("chat_id", string_of_int chat_id)] +? ("reply_to_message_id", string_of_int <$> reply_to_message_id)
                                                          +? ("reply_markup", Yojson.Safe.to_string <$> (ReplyMarkup.prepare <$> reply_markup)) in
        InputFile.multipart_body fields ("document", document, "text/plain") (* FIXME? *)
  end
end

module Sticker = struct
  type sticker = {
    file_id   : string;
    width     : int;
    height    : int;
    thumb     : PhotoSize.photo_size option;
    file_size : int option
  }

  let create ~file_id ~width ~height ?(thumb = None) ?(file_size = None) () =
    {file_id; width; height; thumb; file_size}

  let read obj =
    let file_id = the_string @@ get_field "file_id" obj in
    let width = the_int @@ get_field "width" obj in
    let height = the_int @@ get_field "height" obj in
    let thumb = PhotoSize.read <$> get_opt_field "thumb" obj in
    let file_size = the_int <$> get_opt_field "file_size" obj in
    create ~file_id ~width ~height ~thumb ~file_size ()

  module Out = struct
    type sticker = {
      chat_id             : int;
      sticker             : string;
      reply_to_message_id : int option;
      reply_markup        : ReplyMarkup.reply_markup option
    }

    let create ~chat_id ~sticker ?(reply_to = None) ?(reply_markup = None) () =
      {chat_id; sticker; reply_to_message_id = reply_to; reply_markup}

    let prepare = function
    | {chat_id; sticker; reply_to_message_id; reply_markup} ->
      let json = `Assoc ([("chat_id", `Int chat_id);
                          ("sticker", `String sticker)] +? ("reply_to_message_id", this_int <$> reply_to_message_id)
                                                        +? ("reply_markup", ReplyMarkup.prepare <$> reply_markup)) in
      Yojson.Safe.to_string json

    let prepare_multipart = function
      | {chat_id; sticker; reply_to_message_id; reply_markup} ->
        let fields = [("chat_id", string_of_int chat_id)] +? ("reply_to_message_id", string_of_int <$> reply_to_message_id)
                                                          +? ("reply_markup", Yojson.Safe.to_string <$> (ReplyMarkup.prepare <$> reply_markup)) in
        InputFile.multipart_body fields ("sticker", sticker, "image/webp") (* FIXME? *)
  end
end

module Video = struct
  type video = {
    file_id   : string;
    width     : int;
    height    : int;
    duration  : int;
    thumb     : PhotoSize.photo_size option;
    mime_type : string option;
    file_size : int option
  }

  let create ~file_id ~width ~height ~duration ?(thumb = None) ?(mime_type = None) ?(file_size = None) () =
    {file_id; width; height; duration; thumb; mime_type; file_size}

  let read obj =
    let file_id = the_string @@ get_field "file_id" obj in
    let width = the_int @@ get_field "width" obj in
    let height = the_int @@ get_field "height" obj in
    let duration = the_int @@ get_field "duration" obj in
    let thumb = PhotoSize.read <$> get_opt_field "thumb" obj in
    let mime_type = the_string <$> get_opt_field "mime_type" obj in
    let file_size = the_int <$> get_opt_field "file_size" obj in
    create ~file_id ~width ~height ~duration ~thumb ~mime_type ~file_size ()

  module Out = struct
    type video = {
      chat_id             : int;
      video               : string;
      duration            : int option;
      caption             : string option;
      reply_to_message_id : int option;
      reply_markup        : ReplyMarkup.reply_markup option
    }

    let create ~chat_id ~video ?(duration = None) ?(caption = None) ?(reply_to = None) ?(reply_markup = None) () =
      {chat_id; video; duration; caption; reply_to_message_id = reply_to; reply_markup}

    let prepare = function
    | {chat_id; video; duration; caption; reply_to_message_id; reply_markup} ->
      let json = `Assoc ([("chat_id", `Int chat_id);
                          ("video", `String video)] +? ("duration", this_int <$> duration)
                                                    +? ("caption", this_string <$> caption)
                                                    +? ("reply_to_message_id", this_int <$> reply_to_message_id)
                                                    +? ("reply_markup", ReplyMarkup.prepare <$> reply_markup)) in
      Yojson.Safe.to_string json

    let prepare_multipart = function
      | {chat_id; video; duration; caption; reply_to_message_id; reply_markup} ->
        let fields = [("chat_id", string_of_int chat_id)] +? ("duration", string_of_int <$> duration)
                                                          +? ("caption", caption)
                                                          +? ("reply_to_message_id", string_of_int <$> reply_to_message_id)
                                                          +? ("reply_markup", Yojson.Safe.to_string <$> (ReplyMarkup.prepare <$> reply_markup)) in
        let open Batteries.String in
        let mime =
          if ends_with video ".mp4" then "video/mp4" else
          if ends_with video ".mov" then "video/quicktime" else
          if ends_with video ".avi" then "video/x-msvideo" else
          if ends_with video ".webm" then "video/webm" else "text/plain" in
        InputFile.multipart_body fields ("video", video, mime)
  end
end

module Voice = struct
  type voice = {
    file_id   : string;
    duration  : int;
    mime_type : string option;
    file_size : int option
  }

  let create ~file_id ~duration ?(mime_type = None) ?(file_size = None) () =
    {file_id; duration; mime_type; file_size}

  let read obj =
    let file_id = the_string @@ get_field "file_id" obj in
    let duration = the_int @@ get_field "duration" obj in
    let mime_type = the_string <$> get_opt_field "mime_type" obj in
    let file_size = the_int <$> get_opt_field "file_size" obj in
    create ~file_id ~duration ~mime_type ~file_size ()

  module Out = struct
    type voice = {
      chat_id             : int;
      voice               : string;
      duration            : int option;
      reply_to_message_id : int option;
      reply_markup        : ReplyMarkup.reply_markup option
    }

    let create ~chat_id ~voice ?(duration = None) ?(reply_to = None) ?(reply_markup = None) () =
      {chat_id; voice; duration; reply_to_message_id = reply_to; reply_markup}

    let prepare = function
      | {chat_id; voice; duration; reply_to_message_id; reply_markup} ->
        let json = `Assoc ([("chat_id", `Int chat_id);
                            ("voice", `String voice)] +? ("duration", this_int <$> duration)
                                                      +? ("reply_to_message_id", this_int <$> reply_to_message_id)
                                                      +? ("reply_markup", ReplyMarkup.prepare <$> reply_markup)) in
        Yojson.Safe.to_string json

    let prepare_multipart = function
      | {chat_id; voice; duration; reply_to_message_id; reply_markup} ->
        let fields = [("chat_id", string_of_int chat_id)] +? ("duration", string_of_int <$> duration)
                                                          +? ("reply_to_message_id", string_of_int <$> reply_to_message_id)
                                                          +? ("reply_markup", Yojson.Safe.to_string <$> (ReplyMarkup.prepare <$> reply_markup)) in
        InputFile.multipart_body fields ("voice", voice, "audio/ogg")
  end
end

module Contact = struct
  type contact = {
    phone_number : string;
    first_name   : string;
    last_name    : string option;
    user_id      : int option
  }

  let create ~phone_number ~first_name ?(last_name = None) ?(user_id = None) () =
    {phone_number; first_name; last_name; user_id}

  let read obj =
    let phone_number = the_string @@ get_field "phone_number" obj in
    let first_name = the_string @@ get_field "first_name" obj in
    let last_name = the_string <$> get_opt_field "last_name" obj in
    let user_id = the_int <$> get_opt_field "user_id" obj in
    create ~phone_number ~first_name ~last_name ~user_id ()
end

module Location = struct
  type location = {
    longitude : float;
    latitude  : float
  }

  let create ~longitude ~latitude () =
    {longitude; latitude}

  let read obj =
    let longitude = the_float @@ get_field "longitude" obj in
    let latitude = the_float @@ get_field "latitude" obj in
    create ~longitude ~latitude ()

  module Out = struct
    type location = {
      chat_id             : int;
      latitude            : float;
      longitude           : float;
      reply_to_message_id : int option;
      reply_markup        : ReplyMarkup.reply_markup option
    }

    let create ~chat_id ~latitude ~longitude ?(reply_to = None) ?(reply_markup = None) () =
      {chat_id; latitude; longitude; reply_to_message_id = reply_to; reply_markup}

    let prepare = function
    | {chat_id; latitude; longitude; reply_to_message_id; reply_markup} ->
      let json = `Assoc ([("chat_id", `Int chat_id);
                          ("latitude", `Float latitude);
                          ("longitude", `Float longitude)] +? ("reply_to_message_id", this_int <$> reply_to_message_id)
                                                           +? ("reply_markup", ReplyMarkup.prepare <$> reply_markup)) in
      Yojson.Safe.to_string json
  end
end

module Venue = struct
  type venue = {
    location      : Location.location;
    title         : string;
    address       : string;
    foursquare_id : string option
  }

  let create ~location ~title ~address ?(foursquare_id=None) () =
    {location; title; address; foursquare_id}

  let read obj =
    let location = Location.read @@ get_field "location" obj in
    let title = the_string @@ get_field "title" obj in
    let address = the_string @@ get_field "address" obj in
    let foursquare_id = the_string <$> get_opt_field "foursquare_id" obj in
    create ~location ~title ~address ~foursquare_id ()
end

module UserProfilePhotos = struct
  type user_profile_photos = {
    total_count : int;
    photos      : PhotoSize.photo_size list list
  }

  let create ~total_count ~photos () =
    {total_count; photos}

  let read obj =
    let total_count = the_int @@ get_field "total_count" obj in
    let photos = List.map (fun p -> List.map PhotoSize.read @@ the_list p) @@ the_list @@ get_field "photos" obj in
    create ~total_count ~photos ()
end

module Message = struct
  open Chat
  open User

  type message = {
    message_id              : int;
    from                    : User.user option;
    date                    : int;
    chat                    : Chat.chat;
    forward_from            : User.user option;
    forward_date            : int option;
    reply_to_message        : message option;
    text                    : string option;
    entities                : MessageEntity.message_entity list option;
    audio                   : Audio.audio option;
    document                : Document.document option;
    photo                   : PhotoSize.photo_size list option;
    sticker                 : Sticker.sticker option;
    video                   : Video.video option;
    voice                   : Voice.voice option;
    caption                 : string option;
    contact                 : Contact.contact option;
    location                : Location.location option;
    venue                   : Venue.venue option;
    new_chat_member         : User.user option;
    left_chat_member        : User.user option;
    new_chat_title          : string option;
    new_chat_photo          : PhotoSize.photo_size list option;
    delete_chat_photo       : bool option;
    group_chat_created      : bool option;
    supergroup_chat_created : bool option;
    channel_chat_created    : bool option;
    migrate_to_chat_id      : int option;
    migrate_from_chat_id    : int option;
    pinned_message          : message option
  }

  let create ~message_id ?(from = None) ~date ~chat ?(forward_from = None) ?(forward_date = None) ?(reply_to = None) ?(text = None) ?(entities = None) ?(audio = None) ?(document = None) ?(photo = None) ?(sticker = None) ?(video = None) ?(voice = None) ?(caption = None) ?(contact = None) ?(location = None) ?(venue = None) ?(new_chat_member = None) ?(left_chat_member = None) ?(new_chat_title = None) ?(new_chat_photo = None) ?(delete_chat_photo = None) ?(group_chat_created = None) ?(supergroup_chat_created = None) ?(channel_chat_created = None) ?(migrate_to_chat_id = None) ?(migrate_from_chat_id = None) ?(pinned_message = None) () =
    {message_id; from; date; chat; forward_from; forward_date; reply_to_message = reply_to; text; entities; audio; document; photo; sticker; video; voice; caption; contact; location; venue; new_chat_member; left_chat_member; new_chat_title; new_chat_photo; delete_chat_photo; group_chat_created; supergroup_chat_created; channel_chat_created; migrate_to_chat_id; migrate_from_chat_id; pinned_message}

  let rec read obj =
    let message_id = the_int @@ get_field "message_id" obj in
    let from = User.read <$> get_opt_field "from" obj in
    let date = the_int @@ get_field "date" obj in
    let chat = Chat.read @@ get_field "chat" obj in
    let forward_from = User.read <$> get_opt_field "forward_from" obj in
    let forward_date = the_int <$> get_opt_field "forward_date" obj in
    let reply_to = read <$> get_opt_field "reply_to_message" obj in
    let text = the_string <$> get_opt_field "text" obj in
    let entities = List.map MessageEntity.read <$> (the_list <$> get_opt_field "entities" obj) in
    let audio = Audio.read <$> get_opt_field "audio" obj in
    let document = Document.read <$> get_opt_field "document" obj in
    let photo = List.map PhotoSize.read <$> (the_list <$> get_opt_field "photo" obj) in
    let sticker = Sticker.read <$> get_opt_field "sticker" obj in
    let video = Video.read <$> get_opt_field "video" obj in
    let voice = Voice.read <$> get_opt_field "voice" obj in
    let caption = the_string <$> get_opt_field "caption" obj in
    let contact = Contact.read <$> get_opt_field "contact" obj in
    let location = Location.read <$> get_opt_field "location" obj in
    let venue = Venue.read <$> get_opt_field "venue" obj in
    let new_chat_member = User.read <$> get_opt_field "new_chat_member" obj in
    let left_chat_member = User.read <$> get_opt_field "left_chat_member" obj in
    let new_chat_title = the_string <$> get_opt_field "new_chat_title" obj in
    let new_chat_photo = List.map PhotoSize.read <$> (the_list <$> get_opt_field "new_chat_photo" obj) in
    let delete_chat_photo = the_bool <$> get_opt_field "delete_chat_photo" obj in
    let group_chat_created = the_bool <$> get_opt_field "group_chat_created" obj in
    let supergroup_chat_created = the_bool <$> get_opt_field "supergroup_chat_created" obj in
    let channel_chat_created = the_bool <$> get_opt_field "channel_chat_created" obj in
    let migrate_to_chat_id = the_int <$> get_opt_field "migrate_to_chat_id" obj in
    let migrate_from_chat_id = the_int <$> get_opt_field "migrate_from_chat_id" obj in
    let pinned_message = read <$> get_opt_field "message" obj in
    create ~message_id ~from ~date ~chat ~forward_from ~forward_date ~reply_to ~text ~entities ~audio ~document ~photo ~sticker ~video ~voice ~caption ~contact ~location ~venue ~new_chat_member ~left_chat_member ~new_chat_title ~new_chat_photo ~delete_chat_photo ~group_chat_created ~supergroup_chat_created ~channel_chat_created ~migrate_to_chat_id ~migrate_from_chat_id ~pinned_message ()

  let get_sender_first_name = function
    | {from = Some user} -> user.first_name
    | {chat = {first_name = Some first_name}} -> first_name
    | _ -> "unknown sender"

  let get_sender_username = function
    | {from = Some {username = Some username}} -> username
    | {chat = {username = Some username}} -> username
    | _ -> ""

  let get_sender msg =
    match get_sender_username msg with
    | "" -> get_sender_first_name msg
    | un -> get_sender_first_name msg ^ " (" ^ un ^ ")"
end

module File = struct
  type file = {
    file_id   : string;
    file_size : int option;
    file_path : string option
  }

  let create ~file_id ?(file_size=None) ?(file_path=None) () =
    {file_id; file_size; file_path}

  let read obj =
    let file_id = the_string @@ get_field "file_id" obj in
    let file_size = the_int <$> get_opt_field "file_size" obj in
    let file_path = the_string <$> get_opt_field "file_path" obj in
    create ~file_id ~file_size ~file_path ()

  let download token file =
    file.file_path >>= fun path ->
    let open Lwt in
    let url = Uri.of_string ("https://api.telegram.org/file/bot" ^ token ^ "/" ^ path) in
    Some (Cohttp_lwt_unix.Client.get url >>= fun (resp, body) ->
          Cohttp_lwt_body.to_string body)
end

module CallbackQuery = struct
  type callback_query = {
    id                : string;
    from              : User.user;
    message           : Message.message option;
    inline_message_id : string option;
    data              : string
  }

  let create ~id ~from ?(message=None) ?(inline_message_id=None) ~data () =
    {id; from; message; inline_message_id; data}

  let read obj =
    let id = the_string @@ get_field "id" obj in
    let from = User.read @@ get_field "from" obj in
    let message = Message.read <$> get_opt_field "message" obj in
    let inline_message_id = the_string <$> get_opt_field "inline_message_id" obj in
    let data = the_string @@ get_field "data" obj in
    create ~id ~from ~message ~inline_message_id ~data ()
end

module InlineQuery = struct
  type inline_query = {
    id     : string;
    from   : User.user;
    query  : string;
    offset : string
  }

  let create ~id ~from ~query ~offset () =
    {id; from; query; offset}

  let read obj =
    let id = the_string @@ get_field "id" obj in
    let from = User.read @@ get_field "from" obj in
    let query = the_string @@ get_field "query" obj in
    let offset = the_string @@ get_field "offset" obj in
    create ~id ~from ~query ~offset ()

  type chosen_inline_result = {
    result_id : string;
    from      : User.user;
    query     : string
  }

  let read_chosen_inline_result obj =
    let result_id = the_string @@ get_field "result_id" obj in
    let from = User.read @@ get_field "from" obj in
    let query = the_string @@ get_field "query" obj in
    {result_id; from; query}

  module Out = struct
    type parse_mode = Markdown | Html

    let string_of_parse_mode = function
      | Markdown -> "Markdown"
      | Html -> "HTML"

    type article = {
      id                       : string;
      title                    : string;
      message_text             : string;
      parse_mode               : parse_mode option;
      disable_web_page_preview : bool option;
      url                      : string option;
      hide_url                 : bool option;
      description              : string option;
      thumb_url                : string option;
      thumb_width              : int option;
      thumb_height             : int option
    }

    type photo = {
      id                       : string;
      photo_url                : string;
      photo_width              : int option;
      photo_height             : int option;
      thumb_url                : string;
      title                    : string option;
      description              : string option;
      caption                  : string option;
      message_text             : string option;
      parse_mode               : parse_mode option;
      disable_web_page_preview : bool option
    }

    type gif = {
      id                       : string;
      gif_url                  : string;
      gif_width                : int option;
      gif_height               : int option;
      thumb_url                : string;
      title                    : string option;
      caption                  : string option;
      message_text             : string option;
      parse_mode               : parse_mode option;
      disable_web_page_preview : bool option
    }

    type mpeg4gif = {
      id                       : string;
      mpeg4_url                : string;
      mpeg4_width              : int option;
      mpeg4_height             : int option;
      thumb_url                : string;
      title                    : string option;
      caption                  : string option;
      message_text             : string option;
      parse_mode               : parse_mode option;
      disable_web_page_preview : bool option
    }

    type video = {
      id                       : string;
      video_url                : string;
      mime_type                : string;
      message_text             : string;
      parse_mode               : parse_mode option;
      disable_web_page_preview : bool option;
      video_width              : int option;
      video_height             : int option;
      video_duration           : int option;
      thumb_url                : string;
      title                    : string;
      description              : string option
    }

    type inline_query_result =
      | Article of article
      | Photo of photo
      | Gif of gif
      | Mpeg4Gif of mpeg4gif
      | Video of video

    let create_article ~id ~title ~message_text ?parse_mode ?disable_web_page_preview ?url ?hide_url ?description ?thumb_url ?thumb_width ?thumb_height () =
      Article {id; title; message_text; parse_mode; disable_web_page_preview; url; hide_url; description; thumb_url; thumb_width; thumb_height}

    let create_photo ~id ~photo_url ?photo_width ?photo_height ~thumb_url ?title ?description ?caption ?message_text ?parse_mode ?disable_web_page_preview () =
      Photo {id; photo_url; photo_width; photo_height; thumb_url; title; description; caption; message_text; parse_mode; disable_web_page_preview}

    let create_gif ~id ~gif_url ?gif_width ?gif_height ~thumb_url ?title ?caption ?message_text ?parse_mode ?disable_web_page_preview () =
      Gif {id; gif_url; gif_width; gif_height; thumb_url; title; caption; message_text; parse_mode; disable_web_page_preview}

    let create_mpeg4gif ~id ~mpeg4_url ?mpeg4_width ?mpeg4_height ~thumb_url ?title ?caption ?message_text ?parse_mode ?disable_web_page_preview () =
      Mpeg4Gif {id; mpeg4_url; mpeg4_width; mpeg4_height; thumb_url; title; caption; message_text; parse_mode; disable_web_page_preview}

    let create_video ~id ~video_url ~mime_type ~message_text ?parse_mode ?disable_web_page_preview ?video_width ?video_height ?video_duration ~thumb_url ~title ?description () =
      Video {id; video_url; mime_type; message_text; parse_mode; disable_web_page_preview; video_width; video_height; video_duration; thumb_url; title; description}

    let prepare = function
      | Article {id; title; message_text; parse_mode; disable_web_page_preview; url; hide_url; description; thumb_url; thumb_width; thumb_height} ->
        `Assoc ([("type", `String "article");
                 ("id", `String id);
                 ("title", `String title);
                 ("message_text", `String message_text)] +? ("parse_mode", this_string <$> (string_of_parse_mode <$> parse_mode))
                                                         +? ("disable_web_page_preview", this_bool <$> disable_web_page_preview)
                                                         +? ("url", this_string <$> url)
                                                         +? ("hide_url", this_bool <$> hide_url)
                                                         +? ("description", this_string <$> description)
                                                         +? ("thumb_url", this_string <$> thumb_url)
                                                         +? ("thumb_width", this_int <$> thumb_width)
                                                         +? ("thumb_height", this_int <$> thumb_height))
      | Photo {id; photo_url; photo_width; photo_height; thumb_url; title; description; caption; message_text; parse_mode; disable_web_page_preview} ->
        `Assoc ([("type", `String "photo");
                 ("id", `String id);
                 ("photo_url", `String photo_url);
                 ("thumb_url", `String thumb_url)] +? ("photo_width", this_int <$> photo_width)
                                                   +? ("photo_height", this_int <$> photo_height)
                                                   +? ("title", this_string <$> title)
                                                   +? ("description", this_string <$> description)
                                                   +? ("caption", this_string <$> caption)
                                                   +? ("message_text", this_string <$> message_text)
                                                   +? ("parse_mode", this_string <$> (string_of_parse_mode <$> parse_mode))
                                                   +? ("disable_web_page_preview", this_bool <$> disable_web_page_preview))
      | Gif {id; gif_url; gif_width; gif_height; thumb_url; title; caption; message_text; parse_mode; disable_web_page_preview} ->
        `Assoc ([("type", `String "gif");
                 ("id", `String id);
                 ("gif_url", `String gif_url);
                 ("thumb_url", `String thumb_url)] +? ("gif_width", this_int <$> gif_width)
                                                   +? ("gif_height", this_int <$> gif_height)
                                                   +? ("title", this_string <$> title)
                                                   +? ("caption", this_string <$> caption)
                                                   +? ("message_text", this_string <$> message_text)
                                                   +? ("parse_mode", this_string <$> (string_of_parse_mode <$> parse_mode))
                                                   +? ("disable_web_page_preview", this_bool <$> disable_web_page_preview))
      | Mpeg4Gif {id; mpeg4_url; mpeg4_width; mpeg4_height; thumb_url; title; caption; message_text; parse_mode; disable_web_page_preview} ->
        `Assoc ([("type", `String "mpeg4gif");
                ("id", `String id);
                ("mpeg4_url", `String mpeg4_url);
                ("thumb_url", `String thumb_url)] +? ("mpeg4_width", this_int <$> mpeg4_width)
                                                  +? ("mpeg4_height", this_int <$> mpeg4_height)
                                                  +? ("title", this_string <$> title)
                                                  +? ("caption", this_string <$> caption)
                                                  +? ("message_text", this_string <$> message_text)
                                                  +? ("parse_mode", this_string <$> (string_of_parse_mode <$> parse_mode))
                                                  +? ("disable_web_page_preview", this_bool <$> disable_web_page_preview))
      | Video {id; video_url; mime_type; message_text; parse_mode; disable_web_page_preview; video_width; video_height; video_duration; thumb_url; title; description} ->
        `Assoc ([("type", `String "video");
                 ("id", `String id);
                 ("video_url", `String video_url);
                 ("mime_type", `String mime_type);
                 ("message_text", `String message_text);
                 ("thumb_url", `String thumb_url);
                 ("title", `String title)] +? ("parse_mode", this_string <$> (string_of_parse_mode <$> parse_mode))
                                           +? ("video_width", this_int <$> video_width)
                                           +? ("video_height", this_int <$> video_height)
                                           +? ("video_duration", this_int <$> video_duration)
                                           +? ("disable_web_page_preview", this_bool <$> disable_web_page_preview))
  end
end

module ChatAction = struct
  type action =
    | Typing
    | UploadPhoto
    | RecordVideo
    | UploadVideo
    | RecordAudio
    | UploadAudio
    | UploadDocument
    | FindLocation

  let to_string = function
    | Typing -> "typing"
    | UploadPhoto -> "upload_photo"
    | RecordVideo -> "record_video"
    | UploadVideo -> "upload_video"
    | RecordAudio -> "record_audio"
    | UploadAudio -> "upload_audio"
    | UploadDocument -> "upload_document"
    | FindLocation -> "find_location"
end

module Update = struct
  type update = {
    update_id            : int;
    message              : Message.message option;
    inline_query         : InlineQuery.inline_query option;
    chosen_inline_result : InlineQuery.chosen_inline_result option;
    callback_query       : CallbackQuery.callback_query option
  }

  let create ~update_id ?(message=None) ?(inline_query=None) ?(chosen_inline_result=None) ?(callback_query=None) () =
    {update_id; message; inline_query; chosen_inline_result; callback_query}

  let read obj =
    let update_id = the_int @@ get_field "update_id" obj in
    let message = Message.read <$> get_opt_field "message" obj in
    let inline_query = InlineQuery.read <$> get_opt_field "inline_query" obj in
    let chosen_inline_result = InlineQuery.read_chosen_inline_result <$> get_opt_field "chosen_inline_result" obj in
    let callback_query = CallbackQuery.read <$> get_opt_field "callback_query" obj in
    create ~update_id ~message ~inline_query ~chosen_inline_result ~callback_query ()

  let is_message = function
    | {message = Some _} -> true
    | _ -> false

  let is_inline_query = function
    | {inline_query = Some _} -> true
    | _ -> false

  let is_chosen_inline_result = function
    | {chosen_inline_result = Some _} -> true
    | _ -> false

  let is_callback_query = function
    | {callback_query = Some _} -> true
    | _ -> false
end

module Result = struct
  include TelegramUtil.Result
end

module Command = struct
  open Update
  open Message
  open Batteries.String

  type action =
    | Nothing
    | GetMe of (User.user Result.result -> action)
    | SendMessage of int * string * int option * ReplyMarkup.reply_markup option
    | ForwardMessage of int * int * int
    | SendChatAction of int * ChatAction.action
    | SendPhoto of int * string * string option * int option * ReplyMarkup.reply_markup option * (string Result.result -> action)
    | ResendPhoto of int * string * string option * int option * ReplyMarkup.reply_markup option
    | SendAudio of int * string * string * string * int option * ReplyMarkup.reply_markup option * (string Result.result -> action)
    | ResendAudio of int * string * string * string * int option * ReplyMarkup.reply_markup option
    | SendDocument of int * string * int option * ReplyMarkup.reply_markup option * (string Result.result -> action)
    | ResendDocument of int * string * int option * ReplyMarkup.reply_markup option
    | SendSticker of int * string * int option * ReplyMarkup.reply_markup option * (string Result.result -> action)
    | ResendSticker of int * string * int option * ReplyMarkup.reply_markup option
    | SendVideo of int * string * int option * string option * int option * ReplyMarkup.reply_markup option * (string Result.result -> action)
    | ResendVideo of int * string * int option * string option * int option * ReplyMarkup.reply_markup option
    | SendVoice of int * string * int option * ReplyMarkup.reply_markup option * (string Result.result -> action)
    | ResendVoice of int * string * int option * ReplyMarkup.reply_markup option
    | SendLocation of int * float * float * int option * ReplyMarkup.reply_markup option
    | GetUserProfilePhotos of int * int option * int option * (UserProfilePhotos.user_profile_photos Result.result -> action)
    | GetFile of string * (File.file Result.result -> action)
    | GetFile' of string * (string option -> action)
    | DownloadFile of File.file * (string option -> action)
    | AnswerInlineQuery of string * InlineQuery.Out.inline_query_result list * int option * bool option * string option
    | GetUpdates of (Update.update list Result.result -> action)
    | PeekUpdate of (Update.update Result.result -> action)
    | PopUpdate of (Update.update Result.result -> action)
    | Chain of action * action

  type command = {
    name            : string;
    description     : string;
    mutable enabled : bool;
    run             : message -> action
  }

  let is_command = function
    | {message = Some {text = Some txt}} when starts_with txt "/" -> true
    | _ -> false

  let rec read_command msg cmds = match msg with
    | {text = Some txt; _} -> begin
        let cmp str cmd =
          match nsplit str ~by:" " with
          | [] -> false
          | a::_ -> begin
              match nsplit a ~by:"@" with
              | [] -> false
              | a::_ -> a = cmd
            end in
        match cmds with
        | [] -> Nothing
        | cmd::_ when cmp txt ("/" ^ cmd.name) && cmd.enabled -> cmd.run msg
        | _::cmds -> read_command msg cmds
      end
    | {text = None} -> Nothing

  let read_update = function
    | {message = Some msg} -> read_command msg
    | _ -> fun _ -> Nothing

  let tokenize msg = List.tl @@ nsplit msg ~by:" "

  let make_helper = function
    | {name; description} -> "/" ^ name ^ " - " ^ description

  let rec make_help = function
    | [] -> ""
    | cmd::cmds -> "\n" ^ make_helper cmd ^ make_help cmds
end

module type BOT = sig
  val token : string
  val commands : Command.command list
  val inline : InlineQuery.inline_query -> Command.action
end

module type TELEGRAM_BOT = sig
  val url : string
  val commands : Command.command list
  val inline : InlineQuery.inline_query -> Command.action

  val get_me : User.user Result.result Lwt.t
  val send_message : chat_id:int -> text:string -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> unit Result.result Lwt.t
  val forward_message : chat_id:int -> from_chat_id:int -> message_id:int -> unit Result.result Lwt.t
  val send_chat_action : chat_id:int -> action:ChatAction.action -> unit Result.result Lwt.t
  val send_photo : chat_id:int -> photo:string -> ?caption:string option -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> string Result.result Lwt.t
  val resend_photo : chat_id:int -> photo:string -> ?caption:string option -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> unit Result.result Lwt.t
  val send_audio : chat_id:int -> audio:string -> performer:string -> title:string -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> string Result.result Lwt.t
  val resend_audio : chat_id:int -> audio:string -> performer:string -> title:string -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> unit Result.result Lwt.t
  val send_document : chat_id:int -> document:string -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> string Result.result Lwt.t
  val resend_document : chat_id:int -> document:string -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> unit Result.result Lwt.t
  val send_sticker : chat_id:int -> sticker:string -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> string Result.result Lwt.t
  val resend_sticker : chat_id:int -> sticker:string -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> unit Result.result Lwt.t
  val send_video : chat_id:int -> video:string -> ?duration:int option -> ?caption:string option -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> string Result.result Lwt.t
  val resend_video : chat_id:int -> video:string -> ?duration:int option -> ?caption:string option -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> unit Result.result Lwt.t
  val send_voice : chat_id:int -> voice:string -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> string Result.result Lwt.t
  val resend_voice : chat_id:int -> voice:string -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> unit Result.result Lwt.t
  val send_location : chat_id:int -> latitude:float -> longitude:float -> reply_to:int option -> reply_markup:ReplyMarkup.reply_markup option -> unit Result.result Lwt.t
  val get_user_profile_photos : user_id:int -> offset:int option -> limit:int option -> UserProfilePhotos.user_profile_photos Result.result Lwt.t
  val get_file : file_id:string -> File.file Result.result Lwt.t
  val get_file' : file_id:string -> string option Lwt.t
  val download_file : file:File.file -> string option Lwt.t
  val answer_inline_query : inline_query_id:string -> results:InlineQuery.Out.inline_query_result list -> ?cache_time:int option -> ?is_personal:bool option -> ?next_offset:string option -> unit -> unit Result.result Lwt.t
  val get_updates : Update.update list Result.result Lwt.t
  val peek_update : Update.update Result.result Lwt.t
  val pop_update : ?run_cmds:bool -> unit -> Update.update Result.result Lwt.t
end

module Mk (B : BOT) = struct
  open Lwt
  open Cohttp
  open Cohttp_lwt_unix

  open Command

  let url = "https://api.telegram.org/bot" ^ B.token ^ "/"
  let rec commands =
    let open Chat in
    let open Message in
    {name = "help"; description = "Show this message"; enabled = true; run = function
         | {chat} -> SendMessage (chat.id, "Commands:" ^ Command.make_help commands, None, None)} :: B.commands
  let inline = B.inline

  let get_me =
    Client.get (Uri.of_string (url ^ "getMe")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (User.read @@ get_field "result" obj)
    | _ -> Result.Failure (the_string @@ get_field "description" obj)

  let send_message ~chat_id ~text ~reply_to ~reply_markup =
    let json = `Assoc ([("chat_id", `Int chat_id);
                        ("text", `String text)] +? ("reply_to_message_id", this_int <$> reply_to)
                                                +? ("reply_markup", ReplyMarkup.prepare <$> reply_markup)) in
    let body = Yojson.Safe.to_string json in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendMessage")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure (the_string @@ get_field "description" obj)

  let forward_message ~chat_id ~from_chat_id ~message_id =
    let json = `Assoc [("chat_id", `Int chat_id);
                       ("from_chat_id", `Int from_chat_id);
                       ("message_id", `Int message_id)] in
    let body = Yojson.Safe.to_string json in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "forwardMessage")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure (the_string @@ get_field "description" obj)

  let send_chat_action ~chat_id ~action =
    let json = `Assoc [("chat_id", `Int chat_id);
                       ("action", `String (ChatAction.to_string action))] in
    let body = Yojson.Safe.to_string json in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendChatAction")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure (the_string @@ get_field "description" obj)

  let send_photo ~chat_id ~photo ?(caption = None) ~reply_to ~reply_markup =
    let boundary = "--1234567890" in
    PhotoSize.Out.prepare_multipart (PhotoSize.Out.create ~chat_id ~photo ~caption ~reply_to ~reply_markup ()) boundary >>= fun body ->
    let headers = Cohttp.Header.init_with "Content-Type" ("multipart/form-data; boundary=" ^ boundary) in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendPhoto")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (the_string @@ get_field "file_id" @@ List.hd @@ the_list @@ get_field "photo" @@ get_field "result" obj)
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let resend_photo ~chat_id ~photo ?(caption = None) ~reply_to ~reply_markup =
    let body = PhotoSize.Out.prepare @@ PhotoSize.Out.create ~chat_id ~photo ~caption ~reply_to ~reply_markup () in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendPhoto")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let send_audio ~chat_id ~audio ~performer ~title ~reply_to ~reply_markup =
    let boundary = "---1234567890" in
    Audio.Out.prepare_multipart (Audio.Out.create ~chat_id ~audio ~performer ~title ~reply_to ~reply_markup ()) boundary >>= fun body ->
    let headers = Cohttp.Header.init_with "Content-Type" ("multipart/form-data; boundary=" ^ boundary) in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendAudio")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (the_string @@ get_field "file_id" @@ get_field "audio" @@ get_field "result" obj)
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let resend_audio ~chat_id ~audio ~performer ~title ~reply_to ~reply_markup =
    let body = Audio.Out.prepare @@ Audio.Out.create ~chat_id ~audio ~performer ~title ~reply_to ~reply_markup () in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendAudio")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let send_document ~chat_id ~document ~reply_to ~reply_markup =
    let boundary = "--1234567890" in
    Document.Out.prepare_multipart (Document.Out.create ~chat_id ~document ~reply_to ~reply_markup ()) boundary >>= fun body ->
    let headers = Cohttp.Header.init_with "Content-Type" ("multipart/form-data; boundary=" ^ boundary) in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendDocument")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (the_string @@ get_field "file_id" @@ get_field "document" @@ get_field "result" obj)
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let resend_document ~chat_id ~document ~reply_to ~reply_markup =
    let body = Document.Out.prepare @@ Document.Out.create ~chat_id ~document ~reply_to ~reply_markup () in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendDocument")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

   let send_video ~chat_id ~video ?(duration = None) ?(caption = None) ~reply_to ~reply_markup =
    let boundary = "--1234567890" in
    Video.Out.prepare_multipart (Video.Out.create ~chat_id ~video ~duration ~caption ~reply_to ~reply_markup ()) boundary >>= fun body ->
    let headers = Cohttp.Header.init_with "Content-Type" ("multipart/form-data; boundary=" ^ boundary) in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendVideo")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (the_string @@ get_field "file_id" @@ get_field "video" @@ get_field "result" obj)
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let resend_video ~chat_id ~video ?(duration = None) ?(caption = None) ~reply_to ~reply_markup =
    let body = Video.Out.prepare @@ Video.Out.create ~chat_id ~video ~duration ~caption ~reply_to ~reply_markup () in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendVideo")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

   let send_sticker ~chat_id ~sticker ~reply_to ~reply_markup =
    let boundary = "--1234567890" in
    Sticker.Out.prepare_multipart (Sticker.Out.create ~chat_id ~sticker ~reply_to ~reply_markup ()) boundary >>= fun body ->
    let headers = Cohttp.Header.init_with "Content-Type" ("multipart/form-data; boundary=" ^ boundary) in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendSticker")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (the_string @@ get_field "file_id" @@ get_field "sticker" @@ get_field "result" obj)
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let resend_sticker ~chat_id ~sticker ~reply_to ~reply_markup =
    let body = Sticker.Out.prepare @@ Sticker.Out.create ~chat_id ~sticker ~reply_to ~reply_markup () in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendSticker")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let send_voice ~chat_id ~voice ~reply_to ~reply_markup =
    let boundary = "---1234567890" in
    Voice.Out.prepare_multipart (Voice.Out.create ~chat_id ~voice ~reply_to ~reply_markup ()) boundary >>= fun body ->
    let headers = Cohttp.Header.init_with "Content-Type" ("multipart/form-data; boundary=" ^ boundary) in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendVoice")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (the_string @@ get_field "file_id" @@ get_field "voice" @@ get_field "result" obj)
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let resend_voice ~chat_id ~voice ~reply_to ~reply_markup =
    let body = Voice.Out.prepare @@ Voice.Out.create ~chat_id ~voice ~reply_to ~reply_markup () in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendVoice")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let send_location ~chat_id ~latitude ~longitude ~reply_to ~reply_markup =
    let body = Location.Out.prepare @@ Location.Out.create ~chat_id ~latitude ~longitude ~reply_to ~reply_markup () in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "sendLocation")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let get_user_profile_photos ~user_id ~offset ~limit =
    let body = `Assoc ([("user_id", `Int user_id)] +? ("offset", this_int <$> offset)
                                                   +? ("limit", this_int <$> limit)) |> Yojson.Safe.to_string in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "getUserProfilePhotos")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (get_field "result" obj |> UserProfilePhotos.read)
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let get_file ~file_id =
    let body = `Assoc ["file_id", `String file_id] |> Yojson.Safe.to_string in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "getFile")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (get_field "result" obj |> File.read)
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let download_file ~file =
    match File.download B.token file with
    | Some computation -> computation >>= fun res -> return (Some res)
    | None -> return None

  let get_file' ~file_id =
    get_file ~file_id >>= function
    | Result.Success file -> download_file ~file
    | Result.Failure _ -> return None

  let answer_inline_query ~inline_query_id ~results ?(cache_time=None) ?(is_personal=None) ?(next_offset=None) () =
    let results' = List.map (fun result -> InlineQuery.Out.prepare result) results in
    let body = `Assoc ([("inline_query_id", `String inline_query_id);
                        ("results", `List results')] +? ("cache_time", this_int <$> cache_time)
                                                     +? ("is_personal", this_bool <$> is_personal)
                                                     +? ("next_offset", this_string <$> next_offset)) |> Yojson.Safe.to_string in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "answerInlineQuery")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success ()
    | _ -> Result.Failure ((fun x -> print_endline x; x) @@ the_string @@ get_field "description" obj)

  let get_updates =
    Client.get (Uri.of_string (url ^ "getUpdates")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    return @@ match get_field "ok" obj with
    | `Bool true -> Result.Success (List.map Update.read @@ the_list @@ get_field "result" obj)
    | _ -> Result.Failure (the_string @@ get_field "description" obj)

  let offset = ref 0
  let clear_update () =
    let json = `Assoc [("offset", `Int !offset);
                       ("limit", `Int 0)] in
    let body = Yojson.Safe.to_string json in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "getUpdates")) >>= fun _ ->
    return ()

  let peek_update =
    let open Update in
    let json = `Assoc [("offset", `Int 0);
                       ("limit", `Int 1)] in
    let body = Yojson.Safe.to_string json in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "getUpdates")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    let open Result in
    Lwt.return @@ match get_field "ok" obj with
    | `Bool true -> Update.read <$> (hd_ @@ the_list @@ get_field "result" obj)
    | _ -> Failure (the_string @@ get_field "description" obj)

  let rec pop_update ?(run_cmds=true) () =
    let open Update in
    let json = `Assoc [("offset", `Int !offset);
                       ("limit", `Int 1)] in
    let body = Yojson.Safe.to_string json in
    let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
    Client.post ~headers ~body:(Cohttp_lwt_body.of_string body) (Uri.of_string (url ^ "getUpdates")) >>= fun (resp, body) ->
    Cohttp_lwt_body.to_string body >>= fun json ->
    let obj = Yojson.Safe.from_string json in
    match get_field "ok" obj with
    | `Bool true -> begin
        let open Result in
        (* Get the update number for the latest message (the head of the list), if it exists *)
        let update = Update.read <$> (hd_ @@ the_list @@ get_field "result" obj) in
        (* Set the offset to either: the current offset OR the latest update + 1, if one exists *)
        offset := default !offset ((fun update -> update.update_id + 1) <$> update);
        let open Lwt in
        (* Clear the last update and then *)
        clear_update () >>= fun () ->
        (* If command execution is enabled: if there's an update and it has an inline_query field *)
        if run_cmds && default false (Update.is_inline_query <$> update) then begin
          (* Run the evaluator on the inline_query of the update and throw away the result *)
          ignore ((function {inline_query = Some inline_query} -> evaluator @@ inline inline_query | _ -> return ()) <$> update);
          (* And then return just the ID of the last update if it succeeded *)
          return @@ ((fun update -> Update.create update.update_id ()) <$> update)
        (* If command execution is enabled: if there's an update and it's a command... *)
           end else if run_cmds && default false (Command.is_command <$> update) then begin
          (* Run the evaluator on the result of the command, if the update exists *)
          ignore ((fun update -> evaluator @@ Command.read_update update commands) <$> update);
          (* And then return just the ID of the last update if it succeeded *)
          return @@ ((fun update -> Update.create update.update_id ()) <$> update)
        end else return update (* Otherwise, return the last update *)
      end
    | _ -> return @@ Result.Failure (the_string @@ get_field "description" obj)

  and evaluator = function
    | Nothing -> return ()
    | GetMe f -> get_me >>= fun x -> evaluator (f x)
    | SendMessage (chat_id, text, reply_to, reply_markup) -> send_message ~chat_id ~text ~reply_to ~reply_markup >>= fun _ -> return ()
    | ForwardMessage (chat_id, from_chat_id, message_id) -> forward_message ~chat_id ~from_chat_id ~message_id >>= fun _ -> return ()
    | SendChatAction (chat_id, action) -> send_chat_action ~chat_id ~action >>= fun _ -> return ()
    | SendPhoto (chat_id, photo, caption, reply_to, reply_markup, f) -> send_photo ~chat_id ~photo ~caption ~reply_to ~reply_markup >>= fun x -> evaluator (f x)
    | ResendPhoto (chat_id, photo, caption, reply_to, reply_markup) -> resend_photo ~chat_id ~photo ~caption ~reply_to ~reply_markup >>= fun _ -> return ()
    | SendAudio (chat_id, audio, performer, title, reply_to, reply_markup, f) -> send_audio ~chat_id ~audio ~performer ~title ~reply_to ~reply_markup >>= fun x -> evaluator (f x)
    | ResendAudio (chat_id, audio, performer, title, reply_to, reply_markup) -> resend_audio ~chat_id ~audio ~performer ~title ~reply_to ~reply_markup >>= fun _ -> return ()
    | SendDocument (chat_id, document, reply_to, reply_markup, f) -> send_document ~chat_id ~document ~reply_to ~reply_markup >>= fun x -> evaluator (f x)
    | ResendDocument (chat_id, document, reply_to, reply_markup) -> resend_document ~chat_id ~document ~reply_to ~reply_markup >>= fun _ -> return ()
    | SendSticker (chat_id, sticker, reply_to, reply_markup, f) -> send_sticker ~chat_id ~sticker ~reply_to ~reply_markup >>= fun x -> evaluator (f x)
    | ResendSticker (chat_id, sticker, reply_to, reply_markup) -> resend_sticker ~chat_id ~sticker ~reply_to ~reply_markup >>= fun _ -> return ()
    | SendVideo (chat_id, video, duration, caption, reply_to, reply_markup, f) -> send_video ~chat_id ~video ~duration ~caption ~reply_to ~reply_markup >>= fun x -> evaluator (f x)
    | ResendVideo (chat_id, video, duration, caption, reply_to, reply_markup) -> resend_video ~chat_id ~video ~duration ~caption ~reply_to ~reply_markup >>= fun _ -> return ()
    | SendVoice (chat_id, voice, reply_to, reply_markup, f) -> send_voice ~chat_id ~voice ~reply_to ~reply_markup >>= fun x -> evaluator (f x)
    | ResendVoice (chat_id, voice, reply_to, reply_markup) -> resend_voice ~chat_id ~voice ~reply_to ~reply_markup >>= fun _ -> return ()
    | SendLocation (chat_id, latitude, longitude, reply_to, reply_markup) -> send_location ~chat_id ~latitude ~longitude ~reply_to ~reply_markup >>= fun _ -> return ()
    | GetUserProfilePhotos (user_id, offset, limit, f) -> get_user_profile_photos ~user_id ~offset ~limit >>= fun x -> evaluator (f x)
    | GetFile (file_id, f) -> get_file ~file_id >>= fun x -> evaluator (f x)
    | GetFile' (file_id, f) -> get_file' ~file_id >>= fun x -> evaluator (f x)
    | DownloadFile (file, f) -> download_file ~file >>= fun x -> evaluator (f x)
    | AnswerInlineQuery (inline_query_id, results, cache_time, is_personal, next_offset) -> answer_inline_query ~inline_query_id ~results ~cache_time ~is_personal ~next_offset () >>= fun _ -> return ()
    | GetUpdates f -> get_updates >>= fun x -> evaluator (f x)
    | PeekUpdate f -> peek_update >>= fun x -> evaluator (f x)
    | PopUpdate f -> pop_update () >>= fun x -> evaluator (f x)
    | Chain (first, second) -> evaluator first >>= fun _ -> evaluator second
end
