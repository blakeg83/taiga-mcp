using System.ComponentModel;
using ModelContextProtocol.Server;
using TaigaMCP.Api;
using TaigaMCP.Models;

namespace TaigaMCP.Tools;

[McpServerToolType]
public sealed class WorkItemCommentTools
{
    private readonly IssueApi _issues;
    private readonly UserStoryApi _userStories;
    private readonly TaskApi _tasks;
    private readonly EpicApi _epics;

    public WorkItemCommentTools(
        IssueApi issues,
        UserStoryApi userStories,
        TaskApi tasks,
        EpicApi epics)
    {
        _issues = issues;
        _userStories = userStories;
        _tasks = tasks;
        _epics = epics;
    }

    [McpServerTool(Name = "add_work_item_comment")]
    [Description("Submit one nonblank Markdown or mention-preserving comment to an issue, user story, task, or epic using its supplied nonnegative version. The kind is closed to issue, user_story, task, or epic. Returns the actual resulting version and comment_submitted=true after one confirmed PATCH; it does not return a history-entry ID or retry an ambiguous write.")]
    public async Task<string> AddWorkItemComment(
        [Description("Work-item kind: issue, user_story, task, or epic.")] WorkItemKind kind,
        [Description("Positive internal work-item ID, not the displayed #ref.")] int id,
        [Description("Required current work-item version, zero or greater; forwarded unchanged to Taiga.")] int version,
        [Description("Nonblank comment text. Markdown, line breaks, Unicode, and mentions are preserved.")] string text,
        CancellationToken cancellationToken = default)
    => await ToolErrors.RunAsync(async () =>
    {
        var returnedVersion = kind switch
        {
            WorkItemKind.issue => await _issues.AddCommentAsync(id, version, text, cancellationToken),
            WorkItemKind.user_story => await _userStories.AddCommentAsync(id, version, text, cancellationToken),
            WorkItemKind.task => await _tasks.AddCommentAsync(id, version, text, cancellationToken),
            WorkItemKind.epic => await _epics.AddCommentAsync(id, version, text, cancellationToken),
            _ => throw new ArgumentException("kind must be one of: issue, user_story, task, epic.")
        };

        return ToolResponseJson.Serialize(new WorkItemCommentReceipt
        {
            Kind = kind.ToString(),
            Id = id,
            Version = returnedVersion,
            CommentSubmitted = true
        });
    });
}
