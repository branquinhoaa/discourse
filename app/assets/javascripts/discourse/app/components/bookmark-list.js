import Component from "@ember/component";
import { action } from "@ember/object";
import { dependentKeyCompat } from "@ember/object/compat";
import { service } from "@ember/service";
import { Promise } from "rsvp";
import BookmarkModal from "discourse/components/modal/bookmark";
import { ajax } from "discourse/lib/ajax";
import { BookmarkFormData } from "discourse/lib/bookmark-form-data";
import {
  openLinkInNewTab,
  shouldOpenInNewTab,
} from "discourse/lib/click-track";
import discourseComputed from "discourse-common/utils/decorators";
import I18n from "discourse-i18n";

export default Component.extend({
  dialog: service(),
  modal: service(),
  classNames: ["bookmark-list-wrapper"],

  get canDoBulkActions() {
    return (
      this.currentUser?.canManageTopic && this.bulkSelectHelper?.selected.length
    );
  },

  get selected() {
    return this.bulkSelectHelper?.selected;
  },

  @action
  removeBookmark(bookmark) {
    return new Promise((resolve, reject) => {
      const deleteBookmark = () => {
        bookmark
          .destroy()
          .then(() => {
            this.appEvents.trigger(
              "bookmarks:changed",
              null,
              bookmark.attachedTo()
            );
            this._removeBookmarkFromList(bookmark);
            resolve(true);
          })
          .catch((error) => {
            reject(error);
          });
      };
      if (!bookmark.reminder_at) {
        return deleteBookmark();
      }
      this.dialog.deleteConfirm({
        message: I18n.t("bookmarks.confirm_delete"),
        didConfirm: () => deleteBookmark(),
        didCancel: () => resolve(false),
      });
    });
  },

  @action
  screenExcerptForExternalLink(event) {
    if (event?.target?.tagName === "A") {
      if (shouldOpenInNewTab(event.target.href)) {
        openLinkInNewTab(event, event.target);
      }
    }
  },

  @action
  editBookmark(bookmark) {
    this.modal.show(BookmarkModal, {
      model: {
        bookmark: new BookmarkFormData(bookmark),
        afterSave: (savedData) => {
          this.appEvents.trigger(
            "bookmarks:changed",
            savedData,
            bookmark.attachedTo()
          );
          this.reload();
        },
        afterDelete: () => {
          this.reload();
        },
      },
    });
  },

  @action
  clearBookmarkReminder(bookmark) {
    return ajax(`/bookmarks/${bookmark.id}`, {
      type: "PUT",
      data: { reminder_at: null },
    }).then(() => {
      bookmark.set("reminder_at", null);
    });
  },

  @action
  togglePinBookmark(bookmark) {
    bookmark.togglePin().then(this.reload);
  },

  @discourseComputed
  experimentalBookmarkBulkActionsEnabled() {
    return true;
    // return this.currentUser?.use_experimental_topic_bulk_actions;
    // return this.bulkSelectHelper?.bulkSelectEnabled;
  },

  @dependentKeyCompat // for the classNameBindings
  get bulkSelectEnabled() {
    return this.bulkSelectHelper?.bulkSelectEnabled;
  },

  _removeBookmarkFromList(bookmark) {
    this.content.removeObject(bookmark);
  },

  click(e) {
    const onClick = (sel, callback) => {
      let target = e.target.closest(sel);

      if (target) {
        callback(target);
      }
    };

    onClick("button.bulk-select", () => {
      this.bulkSelectHelper?.toggleBulkSelect();
      this.rerender();
    });

    onClick("input.bulk-select", () => {
      const target = e.target;
      const selected = this.selected;
      const bookmarkId = target.dataset.id;
      const bookmark = this.content.find(
        (item) => item.id.toString() === bookmarkId
      );

      if (target.checked) {
        selected.addObject(bookmark);

        if (this.lastChecked && e.shiftKey) {
          const bulkSelects = Array.from(
              document.querySelectorAll("input.bulk-select")
            ),
            from = bulkSelects.indexOf(target),
            to = bulkSelects.findIndex((el) => el.id === this.lastChecked.id),
            start = Math.min(from, to),
            end = Math.max(from, to);

          bulkSelects
            .slice(start, end)
            .filter((el) => el.checked !== true)
            .forEach((checkbox) => {
              checkbox.click();
            });
        }
        this.set("lastChecked", target);
      } else {
        selected.removeObject(bookmark);
        this.set("lastChecked", null);
      }
    });
  },
});
