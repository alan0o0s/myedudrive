<?php

/**
 * MyEduDrive theme defaults for Nextcloud's supported theme mechanism.
 * Keep implementation identifiers and upstream files intact; override only
 * user-facing product identity.
 */
class OC_Theme {
	public function getBaseUrl(): string {
		return '';
	}

	public function getDocBaseUrl(): string {
		return '';
	}

	public function getTitle(): string {
		return 'MyEduDrive';
	}

	public function getName(): string {
		return 'MyEduDrive';
	}

	public function getHTMLName(): string {
		return 'MyEduDrive';
	}

	public function getProductName(): string {
		return 'MyEduDrive';
	}

	public function getEntity(): string {
		return 'MyEduDrive';
	}

	public function getSlogan(): string {
		return 'Store. Access. Learn. Anywhere.';
	}

	public function getShortFooter(): string {
		return 'MyEduDrive — Store. Access. Learn. Anywhere.';
	}

	public function getLongFooter(): string {
		return 'MyEduDrive — Store. Access. Learn. Anywhere.';
	}

	public function getColorPrimary(): string {
		return '#1769e0';
	}

	public function getColorBackground(): string {
		return '#0d1422';
	}

	public function getScssVariables(): array {
		return ['color-primary' => '#1769e0'];
	}
}
