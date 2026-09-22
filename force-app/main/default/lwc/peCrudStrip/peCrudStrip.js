import { LightningElement, api } from 'lwc';

/**
 * The six object permissions as tiles.
 *
 * Deliberately not peCrudChips: that component is a dense C R U D badge for a
 * list of forty rows, where space is the constraint. Here one object is in
 * focus and the answer is the headline, so each permission gets a named tile
 * and a word — including "Muted", which the letter chips cannot express at all.
 */
export default class PeCrudStrip extends LightningElement {
    @api grants = [];

    get tiles() {
        return (this.grants ?? []).map((g) => {
            let tone = 'deny';
            let text = 'No';

            if (g.muted) {
                tone = 'mute';
                text = 'Muted';
            } else if (g.granted) {
                tone = 'grant';
                text = 'Yes';
            }

            return {
                key: g.name,
                label: g.label ?? g.name,
                text,
                tileClass: `tile tile_${tone}`,
                dotClass: `tdot tdot_${tone}`,
                textClass: `ttext ttext_${tone}`
            };
        });
    }
}
