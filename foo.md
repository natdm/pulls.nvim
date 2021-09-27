## natdm left a review:
*Commented on 2021-09-25T13:26:32Z*
> Here is a review comment<br>
> Here is the second line in the comment..<br>
> And here were some spaces, and the last line.<br>
### lua/pulls/api.lua
```diff
@@ -23,6 +23,10 @@ function M.description_edit(pull_req_no, body)
     return github.update_pull_requests(pull_req_no, {body = body})
 end

+function M.description_edit_title(pull_req_no, title)
```
> natdm at 2021-09-25T13:26:01Z:<br>
> Starting review<br>
> natdm at 2021-09-25T22:48:32Z:<br>
> This is a reply..<br>
> natdm at 2021-09-27T05:33:38Z:<br>
> Another reply. 👎 <br>
### lua/pulls/init.lua
```diff
@@ -140,6 +140,8 @@ local function save_reviews(pull_req_no)
         print("unable to get reviews: " .. reviews.error)
         return
     end
+
```
> natdm at 2021-09-25T13:26:13Z:<br>
> Another review comment<br>
## natdm left a review:
### lua/pulls/api.lua
```diff
@@ -23,6 +23,10 @@ function M.description_edit(pull_req_no, body)
     return github.update_pull_requests(pullreq_no, {body = body})
 end

+function M.description_edit_title(pull_req_no, title)
+    return github.update_pull_requests(pull_req_no, {title = title})
+end
+
```
> natdm at 2021-09-25T13:27:52Z:<br>
> This is a standalone comment on code.<br>
## natdm left a review:
## natdm left a review:
### lua/pulls/api.lua
```diff
@@ -1,4 +1,5 @@
 local util = require('pulls.util')
+local diff = require('pulls.diff')
```
> natdm at 2021-09-25T23:02:47Z:<br>
> This comment is close to the top..<br>
## natdm left a review:
_
