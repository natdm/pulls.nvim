local reviews = require('pulls.github.reviews')
local pr = require('pulls.github.pull_requests')
local comments = require('pulls.github.comments')

-- ideally `/{vcs}/api.lua` is where the api for the vcs is implemented, and they are abstracted at /api.
-- Don't do too much fancy logic in any of the `pulls.github.__` modules. The idea of making it common could go in here and/or /api.lua which *should be the only place importing this*. For now, it's pretty set for just github.
--

-- about comments:
-- /pulls/n/reviews gives the *parent* reviews.
-- /pulls/n/comments gives the comments of the reviews.
-- /issues gives the comments that are not tied to code.

return { --
    get_reviews = reviews.get,
    get_review_comments = reviews.get_comments,
    get_pull_requests = pr.get,
    update_pull_requests = pr.update,
    get_pull_request_diff = pr.get_diff,
    get_pull_request_files = pr.get_files,
    get_comments = comments.get,
    get_issue_comments = comments.get_issue_comments,
    post_comment = comments.new,
    post_comment_reply = comments.reply
}
